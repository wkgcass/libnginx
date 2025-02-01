#include "ngx_as_lib_module.h"
#include "ngx_http.h"

ngx_as_lib_api_t api;
ngx_as_lib_upcall_t* upcall = NULL;

int64_t ngx_as_lib_looptick(void) {
    typeof(upcall) _upcall = upcall;
    if (!_upcall) {
        return -1;
    }
    if (!_upcall->looptick) {
        return -1;
    }
    return _upcall->looptick(&api, _upcall->ud);
}

static void ngx_set_upcall(ngx_as_lib_upcall_t* _upcall) {
    upcall = _upcall;
}

static ngx_as_lib_upcall_t* ngx_get_upcall(void) {
    return upcall;
}

extern ngx_module_t ngx_as_lib_http_module;
static ngx_as_lib_api_t* ngx_as_lib_get_api_from_req(ngx_http_request_t* r) {
    ngx_as_lib_http_loc_conf_t* conf =
        ngx_http_get_module_loc_conf(r, ngx_as_lib_http_module);
    return conf->api;
}
static int64_t ngx_as_lib_get_loc_id_from_req(ngx_http_request_t* r) {
    ngx_as_lib_http_loc_conf_t* conf =
        ngx_http_get_module_loc_conf(r, ngx_as_lib_http_module);
    return conf->id;
}

static intptr_t ngx_add_http_handler(ngx_conf_t* cf, intptr_t phase, ngx_http_handler_pt _h) {
    ngx_http_core_main_conf_t *cmcf = ngx_http_conf_get_module_main_conf(cf, ngx_http_core_module);
    ngx_http_handler_pt* h = ngx_array_push(&cmcf->phases[phase].handlers);
    if (h == NULL) {
        return NGX_ERROR;
    }
    *h = _h;
    return NGX_OK;
}

static intptr_t ngx_http_buf_output_filter(ngx_http_request_t* r, ngx_buf_t* buf) {
    if (buf) {
        ngx_chain_t out = { 0 };
        out.buf = buf;
        buf->last_in_chain = 1;
        return ngx_http_output_filter(r, &out);
    } else {
        return ngx_http_output_filter(r, NULL);
    }
}

static intptr_t ngx_as_lib_add_http_header(ngx_http_request_t* r, ngx_list_t* headers, const char* key, const char* value) {
    int keylen = strlen(key);
    int vallen = strlen(value);
    void* keystr_data = ngx_palloc(r->pool, keylen);
    void* valstr_data = ngx_palloc(r->pool, vallen);

    if (!keystr_data || !valstr_data) {
        return NGX_ERROR;
    }

    memcpy(keystr_data, key, keylen);
    memcpy(valstr_data, value, vallen);

    ngx_table_elt_t* h = ngx_list_push(headers);
    if (!h) {
        return NGX_ERROR;
    }
    h->hash        = r->header_hash;
    h->key.data    = keystr_data;
    h->key.len     = keylen;
    h->value.data  = valstr_data;
    h->value.len   = vallen;
    h->lowcase_key = ngx_pnalloc(r->pool, keylen);
    if (!h->lowcase_key) {
        return NGX_ERROR;
    }
    ngx_strlow(h->lowcase_key, keystr_data, keylen);

    return NGX_OK;
}

#define MAX_SERVER_ID (1024)
extern ngx_http_core_srv_conf_t* ngx_as_lib_http_server_id_confs[MAX_SERVER_ID];
extern ngx_http_request_t* ngx_http_alloc_request(ngx_connection_t* c);
extern void ngx_close_accepted_connection(ngx_connection_t* c);
static ngx_chain_t* ngx_as_lib_dummy_send_chain(ngx_connection_t *c, ngx_chain_t *in, off_t limit) {
    return NGX_CHAIN_ERROR;
}
static ssize_t ngx_as_lib_dummy_recv(ngx_connection_t *c, u_char *buf, size_t size) {
    return NGX_ERROR;
}

static ngx_http_request_t* ngx_as_lib_new_http_dummy_request(intptr_t server_id) {
    if (server_id < 0 || server_id >= MAX_SERVER_ID) {
        return NULL;
    }
    ngx_http_core_srv_conf_t* conf = ngx_as_lib_http_server_id_confs[server_id];
    if (!conf) {
        return NULL;
    }

    ngx_connection_t* c = NULL;
    ngx_pool_t* pool = ngx_create_pool(1024 * 8, ngx_cycle->log);
    if (!pool) {
        goto errout;
    }

    ngx_log_t* log = ngx_palloc(pool, sizeof(ngx_log_t));
    if (!log) {
        goto errout;
    }
    *log = *ngx_cycle->log;

    c = ngx_get_connection(NGX_DUMMY_FD, log);
    if (!c) {
        ngx_destroy_pool(pool);
        goto errout;
    }
    c->pool = pool;
    pool = NULL;

    c->recv = ngx_as_lib_dummy_recv;
    c->send_chain = ngx_as_lib_dummy_send_chain;

    c->read->log  = ngx_cycle->log;
    c->write->log = ngx_cycle->log;

    ngx_http_connection_t* hc = ngx_pcalloc(c->pool, sizeof(ngx_http_connection_t));
    if (!hc) {
        goto errout;
    }
    c->data = hc;
    hc->conf_ctx = conf->ctx;

    ngx_http_log_ctx_t* log_ctx = ngx_pcalloc(c->pool, sizeof(ngx_http_log_ctx_t));
    if (!log_ctx) {
        goto errout;
    }
    c->log->data = log_ctx;

    c->buffer = ngx_pcalloc(c->pool, sizeof(ngx_buf_t));
    if (!c->buffer) {
        goto errout;
    }

    ngx_http_request_t* req = ngx_http_alloc_request(c);
    if (!req) {
        goto errout;
    }
    req->main = req;
    c->data = req;

    req->is_dummy = true;
    return req;
errout:
    if (c) {
        ngx_close_accepted_connection(c);
    }
    if (pool) {
        ngx_destroy_pool(pool);
    }
    return NULL;
}

static intptr_t _ngx_http_subrequest(
        ngx_http_request_t* r, intptr_t method,
        char* uri, char* args, ngx_buf_t* body,
        ngx_http_init_subrequest_t* is,
        ngx_http_post_subrequest_t* cb) {
    ngx_str_t _uri;
    ngx_str_t _args;

    int uri_len = strlen(uri);
    _uri.len = uri_len;
    _uri.data = ngx_pcalloc(r->pool, uri_len);
    if (!_uri.data) {
        return NGX_ERROR;
    }
    memcpy(_uri.data, uri, uri_len);

    if (args) {
        int args_len = strlen(args);
        _args.len = args_len;
        _args.data = ngx_pcalloc(r->pool, args_len);
        if (!_args.data) {
            return NGX_ERROR;
        }
        memcpy(_args.data, args, args_len);
    }

    ngx_http_request_t* sr;
    return ngx_http_subrequest_complex(r,
        method, &_uri, args == NULL ? NULL : &_args,
        true, body, &sr, is, cb,
        NGX_HTTP_SUBREQUEST_IN_MEMORY);
}

static void ngx_as_lib_log(uintptr_t level, const char* content) {
    ngx_log_error(level, ngx_cycle->log, 0, "%s", content);
}

static void _ngx_notify(void) {
    // do nothing
}

struct ngx_as_lib_main_args {
    int    argc;
    char** argv;
    bool   is_primary;
    int    worker_id;
};

extern int ngx_lib_main(int, char**);

static int ngx_as_lib_main(int argc, char** argv) {
    ngx_as_lib_ngx_ff_process = NGX_FF_PROCESS_PRIMARY;
    ngx_as_lib_ngx_worker_id = 0;
    return ngx_lib_main(argc, argv);
}

static void* ngx_as_lib_main_thread(void* arg) {
    struct ngx_as_lib_main_args* args = arg;
    if (args->is_primary) {
        ngx_as_lib_ngx_ff_process = NGX_FF_PROCESS_PRIMARY;
    } else {
        ngx_as_lib_ngx_ff_process = NGX_FF_PROCESS_SECONDARY;
    }
    ngx_as_lib_ngx_worker_id = args->worker_id;
    int ret = ngx_lib_main(args->argc, args->argv);
    for (int i = 0; i < args->argc; ++i) {
        free(args->argv[i]);
    }
    free(args->argv);
    free(args);

    int32_t* retptr = malloc(sizeof(int32_t));
    if (retptr) {
        *retptr = ret;
    }
    return retptr;
}

static int ngx_as_lib_main_thread_for_ff(void* arg) {
    int32_t* p = ngx_as_lib_main_thread(arg);
    int32_t v = *p;
    free(p);
    return v;
}

static int ngx_as_lib_main_new_thread(pthread_t* t, ngx_as_lib_api_t* main_api, int argc, char** argv, bool is_primary, uint32_t cid, uint32_t worker_id) {
    struct ngx_as_lib_main_args* args = malloc(sizeof(struct ngx_as_lib_main_args));
    if (!args) {
        return NGX_ERROR;
    }
    args->is_primary = is_primary;
    args->worker_id = worker_id;
    args->argv = malloc(sizeof(char*) * argc);
    if (!args->argv) {
        free(args);
        return NGX_ERROR;
    }
    memset(args->argv, 0, sizeof(char*) * argc);

    args->argc = argc;
    for (int i = 0; i < argc; ++i) {
        int len = strlen(argv[i]);
        args->argv[i] = malloc(len + 1);
        if (!args->argv[i]) {
            goto errout;
        }
        memcpy(args->argv[i], argv[i], len + 1);
    }

    memset(t, 0, sizeof(pthread_t));
    if (is_primary) {
        int err = pthread_create(t, NULL, ngx_as_lib_main_thread, args);
        if (err) {
            goto errout;
        }
    } else {
        main_api->ff_reg_worker_job(cid, ngx_as_lib_main_thread_for_ff, args);
    }
    return NGX_OK;
errout:
    for (int i = 0; i < argc; ++i) {
        if (!args->argv[i]) {
            break;
        }
        free(args->argv[i]);
    }
    free(args->argv);
    free(args);
    return NGX_ERROR;
}

// api
ngx_as_lib_api_t api = {
    .get_api_from_req       = ngx_as_lib_get_api_from_req,
    .get_loc_id_from_req    = ngx_as_lib_get_loc_id_from_req,
    .get_upcall             = ngx_get_upcall,
    .set_upcall             = ngx_set_upcall,
    .log                    = ngx_as_lib_log,
    .notify                 = _ngx_notify,
    .add_http_handler       = ngx_add_http_handler,
    .pcalloc                = ngx_pcalloc,
    .http_read_client_request_body = ngx_http_read_client_request_body,
    .http_send_header       = ngx_http_send_header,
    .http_buf_output_filter = ngx_http_buf_output_filter,
    .http_finalize_request  = ngx_http_finalize_request,
    .add_http_header        = ngx_as_lib_add_http_header,

    .new_http_dummy_request = ngx_as_lib_new_http_dummy_request,
    .http_run_posted_requests=ngx_http_run_posted_requests,
    .http_subrequest        = _ngx_http_subrequest,

    .main = ngx_as_lib_main,
    .main_new_thread = ngx_as_lib_main_new_thread,
    .ff_reg_worker_job = ff_reg_worker_job,
};

ngx_as_lib_api_t* libngx(void) {
    return &api;
}
