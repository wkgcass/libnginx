#include "ngx_as_lib_module.h"

extern ngx_as_lib_api_t api;
extern ngx_as_lib_upcall_t* upcall;

// conf set
static char* ngx_as_lib_http_server_id_conf_set(ngx_conf_t* cf, ngx_command_t* cmd, void* conf);

static ngx_http_module_t ngx_as_lib_http_server_id_module_ctx = {
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
};

struct ngx_as_lib_http_server_id_conf {
    ngx_int_t id;
};

static ngx_command_t ngx_as_lib_http_server_id_commands[] = {
    {
        ngx_string("server_id"),
        NGX_HTTP_SRV_CONF|NGX_CONF_TAKE1,
        ngx_as_lib_http_server_id_conf_set,
        0,
        offsetof(struct ngx_as_lib_http_server_id_conf, id),
        NULL,
    },
    ngx_null_command
};

ngx_module_t ngx_as_lib_http_server_id_module = {
    NGX_MODULE_V1,
    &ngx_as_lib_http_server_id_module_ctx,
    ngx_as_lib_http_server_id_commands,
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

// impl
#define MAX_SERVER_ID (1024)
ngx_http_core_srv_conf_t* ngx_as_lib_http_server_id_confs[MAX_SERVER_ID];

static char* ngx_as_lib_http_server_id_conf_set(ngx_conf_t* cf, ngx_command_t* cmd, void* unused) {
    struct ngx_as_lib_http_server_id_conf conf = { 0 };
    conf.id = NGX_CONF_UNSET;
    char* err = ngx_conf_set_num_slot(cf, cmd, &conf);
    if (err) {
        return err;
    }

    if (conf.id < 0) {
        return "server id must not be negative";
    }
    if (conf.id >= MAX_SERVER_ID) {
        return "server id must be less than 1024";
    }
    if (ngx_as_lib_http_server_id_confs[conf.id]) {
        return "duplicated server id";
    }

    ngx_http_conf_ctx_t* ctx = cf->ctx;
    ngx_as_lib_http_server_id_confs[conf.id] = ctx->srv_conf[ngx_http_core_module.ctx_index];

    return NGX_OK;
}
