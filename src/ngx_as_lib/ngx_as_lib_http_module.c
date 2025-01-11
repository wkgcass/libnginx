#include "ngx_as_lib_module.h"

extern ngx_as_lib_api_t api;
extern ngx_as_lib_upcall_t* upcall;

// conf set
static char* ngx_as_lib_http_conf_set(ngx_conf_t* cf, ngx_command_t* cmd, void* conf);

// core
static ngx_int_t ngx_as_lib_init_master (ngx_log_t* log);
static ngx_int_t ngx_as_lib_init_module (ngx_cycle_t* cycle);
static ngx_int_t ngx_as_lib_init_process(ngx_cycle_t* cycle);
static ngx_int_t ngx_as_lib_init_thread (ngx_cycle_t* cycle);
static void      ngx_as_lib_exit_thread (ngx_cycle_t* cycle);
static void      ngx_as_lib_exit_process(ngx_cycle_t* cycle);
static void      ngx_as_lib_exit_master (ngx_cycle_t* cycle);

// http
// static ngx_int_t ngx_as_lib_preconfiguration (ngx_conf_t* cf);
static ngx_int_t ngx_as_lib_postconfiguration(ngx_conf_t* cf);
// static void*     ngx_as_lib_create_main_conf (ngx_conf_t* cf);
// static char*     ngx_as_lib_init_main_conf   (ngx_conf_t* cf, void* conf);
// static void*     ngx_as_lib_create_srv_conf  (ngx_conf_t* cf);
// static char*     ngx_as_lib_merge_srv_conf   (ngx_conf_t* cf, void* prev, void* conf);
static void*     ngx_as_lib_create_loc_conf  (ngx_conf_t* cf);
// static char*     ngx_as_lib_merge_loc_conf   (ngx_conf_t* cf, void* prev, void* conf);

static ngx_http_module_t ngx_as_lib_http_module_ctx = {
    NULL, // ngx_as_lib_preconfiguration,
    ngx_as_lib_postconfiguration,
    NULL, // ngx_as_lib_create_main_conf,
    NULL, // ngx_as_lib_init_main_conf,
    NULL, // ngx_as_lib_create_srv_conf,
    NULL, // ngx_as_lib_merge_srv_conf,
    ngx_as_lib_create_loc_conf,
    NULL, // ngx_as_lib_merge_loc_conf,
};

static ngx_command_t ngx_as_lib_http_commands[] = {
   {
        ngx_string("upcall"),
        NGX_HTTP_LOC_CONF|NGX_HTTP_LIF_CONF|NGX_CONF_TAKE1,
        ngx_as_lib_http_conf_set,
        NGX_HTTP_LOC_CONF_OFFSET,
        offsetof(ngx_as_lib_http_loc_conf_t, id),
        NULL,
    },
    ngx_null_command
};

ngx_module_t ngx_as_lib_http_module = {
    NGX_MODULE_V1,
    &ngx_as_lib_http_module_ctx,
    ngx_as_lib_http_commands,
    NGX_HTTP_MODULE,
    ngx_as_lib_init_master,
    ngx_as_lib_init_module,
    ngx_as_lib_init_process,
    ngx_as_lib_init_thread,
    ngx_as_lib_exit_thread,
    ngx_as_lib_exit_process,
    ngx_as_lib_exit_master,
    NGX_MODULE_V1_PADDING
};

// impl
static char* ngx_as_lib_http_conf_set(ngx_conf_t* cf, ngx_command_t* cmd, void* conf) {
    return ngx_conf_set_num_slot(cf, cmd, conf);
}

// core
static ngx_int_t ngx_as_lib_init_master(ngx_log_t* log) {
    typeof(upcall) _upcall = upcall;
    if (!_upcall) {
        return NGX_ERROR;
    }
    if (!_upcall->init_master) {
        return NGX_OK;
    }
    return _upcall->init_master(&api, _upcall->ud, log);
}
static ngx_int_t ngx_as_lib_init_module(ngx_cycle_t* cycle) {
    typeof(upcall) _upcall = upcall;
    if (!_upcall) {
        return NGX_ERROR;
    }
    if (!_upcall->init_module) {
        return NGX_OK;
    }
    return _upcall->init_module(&api, _upcall->ud, cycle);
}
static ngx_int_t ngx_as_lib_init_process(ngx_cycle_t* cycle) {
    typeof(upcall) _upcall = upcall;
    if (!_upcall) {
        return NGX_ERROR;
    }
    if (!_upcall->init_process) {
        return NGX_OK;
    }
    return _upcall->init_process(&api, _upcall->ud, cycle);
}
static ngx_int_t ngx_as_lib_init_thread(ngx_cycle_t* cycle) {
    typeof(upcall) _upcall = upcall;
    if (!_upcall) {
        return NGX_ERROR;
    }
    if (!_upcall->init_thread) {
        return NGX_OK;
    }
    return _upcall->init_thread(&api, _upcall->ud, cycle);
}
static void ngx_as_lib_exit_thread(ngx_cycle_t* cycle) {
    typeof(upcall) _upcall = upcall;
    if (!_upcall) {
        return;
    }
    if (!_upcall->exit_thread) {
        return;
    }
    _upcall->exit_thread(&api, _upcall->ud, cycle);
}
static void ngx_as_lib_exit_process(ngx_cycle_t* cycle) {
    typeof(upcall) _upcall = upcall;
    if (!_upcall) {
        return;
    }
    if (!_upcall->exit_process) {
        return;
    }
    _upcall->exit_process(&api, _upcall->ud, cycle);
}
static void ngx_as_lib_exit_master(ngx_cycle_t* cycle) {
    typeof(upcall) _upcall = upcall;
    if (!_upcall) {
        return;
    }
    if (!_upcall->exit_master) {
        return;
    }
    _upcall->exit_master(&api, _upcall->ud, cycle);
}

// http
static ngx_int_t ngx_as_lib_postconfiguration(ngx_conf_t* cf) {
    typeof(upcall) _upcall = upcall;
    if (!_upcall) {
        return NGX_ERROR;
    }
    if (!_upcall->postconfiguration) {
        return NGX_OK;
    }
    return _upcall->postconfiguration(&api, _upcall->ud, cf);
}

static void* ngx_as_lib_create_loc_conf(ngx_conf_t* cf) {
    ngx_as_lib_http_loc_conf_t* conf = ngx_pcalloc(cf->pool, sizeof(ngx_as_lib_http_loc_conf_t));
    if (!conf) {
        return NULL;
    }
    conf->id  = NGX_CONF_UNSET;
    conf->api = &api;
    return conf;
}
