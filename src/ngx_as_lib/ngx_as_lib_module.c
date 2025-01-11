#include "ngx_as_lib_module.h"
#include "ngx_http.h"

ngx_as_lib_api_t api;
ngx_as_lib_upcall_t* upcall = NULL;

void ngx_as_lib_looptick(void) {
    typeof(upcall) _upcall = upcall;
    if (_upcall->looptick) {
        _upcall->looptick(&api, _upcall->ud);
    }
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

static void ngx_as_lib_log(uintptr_t level, const char* content) {
    ngx_log_error(level, ngx_cycle->log, 0, "%s", content);
}

static void _ngx_notify(void) {
    ngx_notify(NULL);
}

struct ngx_as_lib_main_args {
    int    argc;
    char** argv;
};

extern int ngx_lib_main(int, char**);

static void* ngx_as_lib_main_thread(void* arg) {
    struct ngx_as_lib_main_args* args = arg;
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

static int ngx_as_lib_main_new_thread(pthread_t* t, int argc, char** argv) {
    struct ngx_as_lib_main_args* args = malloc(sizeof(struct ngx_as_lib_main_args));
    if (!args) {
        return NGX_ERROR;
    }
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
    int err = pthread_create(t, NULL, ngx_as_lib_main_thread, args);
    if (err) {
        goto errout;
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

    .main = ngx_lib_main,
    .main_new_thread = ngx_as_lib_main_new_thread,
};

ngx_as_lib_api_t* libngx(void) {
    return &api;
}
