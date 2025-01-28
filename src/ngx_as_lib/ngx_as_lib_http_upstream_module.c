#include "ngx_as_lib_module.h"

extern ngx_as_lib_api_t api;
extern ngx_as_lib_upcall_t* upcall;

static char* ngx_as_lib_http_upstream_conf_set(ngx_conf_t* cf, ngx_command_t* cmd, void* conf);
static ngx_int_t ngx_as_lib_http_upstream_init(ngx_conf_t* cf, ngx_http_upstream_srv_conf_t* us);
static ngx_int_t ngx_as_lib_http_upstream_init_peer(ngx_http_request_t* r, ngx_http_upstream_srv_conf_t* us);
static ngx_int_t ngx_as_lib_http_upstream_get_peer(ngx_peer_connection_t* pc, void* data);
static void ngx_as_lib_http_upstream_free_peer(ngx_peer_connection_t* pc, void* data, ngx_uint_t state);

typedef struct {
    ngx_http_upstream_rr_peers_t parent;

    ngx_int_t         id;
    ngx_as_lib_api_t* api;
} ngx_as_lib_http_upstream_conf_t;

static ngx_command_t ngx_as_lib_http_upstream_commands[] = {
    {
        ngx_string("upcall"),
        NGX_HTTP_UPS_CONF|NGX_CONF_TAKE1,
        ngx_as_lib_http_upstream_conf_set,
        0,
        offsetof(ngx_as_lib_http_upstream_conf_t, id),
        NULL,
    },
    ngx_null_command
};

static ngx_http_module_t ngx_as_lib_http_upstream_module_ctx = {
    NULL,                                  /* preconfiguration */
    NULL,                                  /* postconfiguration */

    NULL,                                  /* create main configuration */
    NULL,                                  /* init main configuration */

    NULL,                                  /* create server configuration */
    NULL,                                  /* merge server configuration */

    NULL,                                  /* create location configuration */
    NULL                                   /* merge location configuration */
};

ngx_module_t ngx_as_lib_http_upstream_module = {
    NGX_MODULE_V1,
    &ngx_as_lib_http_upstream_module_ctx,
    ngx_as_lib_http_upstream_commands,
    NGX_HTTP_MODULE,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    NGX_MODULE_V1_PADDING
};

static char* ngx_as_lib_http_upstream_conf_set(ngx_conf_t* cf, ngx_command_t* cmd, void* conf) {
    ngx_http_upstream_srv_conf_t* uscf =
        ngx_http_conf_get_module_srv_conf(cf, ngx_http_upstream_module);
    if (uscf->peer.init_upstream) {
        return "load balancing method redefined";
    }
    ngx_as_lib_http_upstream_conf_t* uconf =
        ngx_pcalloc(cf->pool, sizeof(ngx_as_lib_http_upstream_conf_t));
    if (!uconf) {
        return "no memory for ngx_as_lib upstream conf";
    }
    uconf->id = NGX_CONF_UNSET;
    uconf->api = &api;
    char* err = ngx_conf_set_num_slot(cf, cmd, uconf);
    if (err) {
        return err;
    }
    uscf->peer.data = uconf;
    uscf->peer.init_upstream = ngx_as_lib_http_upstream_init;
    uscf->flags = NGX_HTTP_UPSTREAM_CREATE;
    return NGX_CONF_OK;
}

static ngx_int_t ngx_as_lib_http_upstream_init(ngx_conf_t* cf, ngx_http_upstream_srv_conf_t* us) {
    ngx_as_lib_http_upstream_conf_t* data = us->peer.data;
    us->peer.data = NULL;
    if (ngx_http_upstream_init_round_robin(cf, us) != NGX_OK) {
        return NGX_ERROR;
    }
    data->parent = *((ngx_http_upstream_rr_peers_t*) us->peer.data);
    us->peer.data = data;
    us->peer.init = ngx_as_lib_http_upstream_init_peer;
    return NGX_OK;
}

struct ngx_as_lib_http_upstream_inst {
    ngx_http_upstream_rr_peer_data_t parent;

    ngx_as_lib_http_upstream_conf_t* conf;
    ngx_http_request_t* r;
};

static ngx_int_t ngx_as_lib_http_upstream_init_peer(ngx_http_request_t* r, ngx_http_upstream_srv_conf_t* us) {
    ngx_as_lib_http_upstream_conf_t* conf = us->peer.data;
    struct ngx_as_lib_http_upstream_inst* inst = ngx_pcalloc(r->pool,
        sizeof(struct ngx_as_lib_http_upstream_inst));
    if (!inst) {
        ngx_log_error(NGX_LOG_ERR, ngx_cycle->log, 0, "no memory for ngx_as_lib upstream inst");
        return NGX_ERROR;
    }
    r->upstream->peer.data = inst;
    ngx_int_t err = ngx_http_upstream_init_round_robin_peer(r, us);
    if (err) {
        return err;
    }

    inst->conf = conf;
    inst->r = r;

    r->upstream->peer.get  = ngx_as_lib_http_upstream_get_peer;
    r->upstream->peer.free = ngx_as_lib_http_upstream_free_peer;
    return NGX_OK;
}

static ngx_int_t ngx_as_lib_http_upstream_get_peer(ngx_peer_connection_t* pc, void* data) {
    struct ngx_as_lib_http_upstream_inst* inst = data;

    typeof(upcall) _upcall = upcall;
    if (!_upcall) {
        return NGX_ERROR;
    }
    if (!_upcall->get_upstream_peer) {
        return NGX_ERROR;
    }

    ngx_int_t err = ngx_http_upstream_get_round_robin_peer(pc, data);
    if (err) {
        return err;
    }
    pc->name = NULL;

    err = _upcall->get_upstream_peer(inst->conf->api, _upcall->ud, inst->r, inst->conf->id, pc);

    // generate pc->name
    if (err == NGX_OK && !pc->name) {
        pc->name = ngx_pcalloc(inst->r->pool, sizeof(ngx_str_t) + 48); // 48:'['[1]+ipv6[39]+']'[1]+:[1]+port[5]+\0[1]
        if (!pc->name) {
            ngx_log_error(NGX_LOG_ERR, pc->log, 0, "no memory for peer_conn->name");
            return NGX_ERROR;
        }
        pc->name->data = ((u_char*)pc->name) + sizeof(ngx_str_t) + 1;
        char portstr[6];
        getnameinfo(pc->sockaddr, pc->socklen, ((char*) pc->name->data), 40, portstr, 6, NI_NUMERICHOST | NI_NUMERICSERV);
        int hostlen = strlen((char*) pc->name->data);

        bool is_v6 = pc->socklen > sizeof(struct sockaddr_in);
        if (is_v6) {
            pc->name->data -= 1;
            pc->name->data[0] = '[';
            pc->name->data[1 + hostlen] = ']';
            pc->name->data[1 + hostlen + 1] = ':';
            memcpy(pc->name->data + 1 + hostlen + 1 + 1, portstr, 6);
            pc->name->len = 1 + hostlen + 1 + 1 + strlen(portstr);
        } else {
            pc->name->data[hostlen] = ':';
            memcpy(pc->name->data + hostlen + 1, portstr, 6);
            pc->name->len = hostlen + 1 + strlen(portstr);
        }
    }
    return err;
}

static void ngx_as_lib_http_upstream_free_peer(ngx_peer_connection_t* pc, void* data, ngx_uint_t state) {
    state &= ~NGX_PEER_FAILED;
    ngx_http_upstream_free_round_robin_peer(pc, data, state);
}
