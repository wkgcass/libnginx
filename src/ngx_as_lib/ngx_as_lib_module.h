#ifndef _NGX_AS_LIB_MODULE_H_
#define _NGX_AS_LIB_MODULE_H_

#include "ngx_http.h"
#include "ngx_http_config.h"
#include <inttypes.h>
#include <pthread.h>

struct ngx_as_lib_api_s;
typedef struct ngx_as_lib_api_s ngx_as_lib_api_t;

struct ngx_as_lib_upcall_s {
    void* ud;

    int64_t (*looptick)(ngx_as_lib_api_t* api, void* ud);

    // conf set callback
    // char* (*http_conf_set)(ngx_conf_t* cf, ngx_command_t* cmd, void* conf);

    // core
    intptr_t (*init_master) (ngx_as_lib_api_t* api, void* ud, ngx_log_t* log);
    intptr_t (*init_module) (ngx_as_lib_api_t* api, void* ud, ngx_cycle_t* cycle);
    intptr_t (*init_process)(ngx_as_lib_api_t* api, void* ud, ngx_cycle_t* cycle);
    intptr_t (*init_thread) (ngx_as_lib_api_t* api, void* ud, ngx_cycle_t* cycle);
    void     (*exit_thread) (ngx_as_lib_api_t* api, void* ud, ngx_cycle_t* cycle);
    void     (*exit_process)(ngx_as_lib_api_t* api, void* ud, ngx_cycle_t* cycle);
    void     (*exit_master) (ngx_as_lib_api_t* api, void* ud, ngx_cycle_t* cycle);

    // http
    // intptr_t(*preconfiguration) (ngx_as_lib_api_t* api, void* ud, ngx_conf_t* cf);
    intptr_t(*postconfiguration)(ngx_as_lib_api_t* api, void* ud, ngx_conf_t* cf);
    // void*  (*create_main_conf) (ngx_as_lib_api_t* api, void* ud, ngx_conf_t* cf);
    // char*  (*init_main_conf)   (ngx_as_lib_api_t* api, void* ud, ngx_conf_t* cf, void* conf);
    // void*  (*create_srv_conf)  (ngx_as_lib_api_t* api, void* ud, ngx_conf_t* cf);
    // char*  (*merge_srv_conf)   (ngx_as_lib_api_t* api, void* ud, ngx_conf_t* cf, void* prev, void* conf);
    // void*  (*create_loc_conf)  (ngx_as_lib_api_t* api, void* ud, ngx_conf_t* cf);
    // char*  (*merge_loc_conf)   (ngx_as_lib_api_t* api, void* ud, ngx_conf_t* cf, void* prev, void* conf);
    intptr_t(*get_upstream_peer)(ngx_as_lib_api_t*api, void* ud, ngx_http_request_t* r, uintptr_t id, ngx_peer_connection_t* pc);
};
typedef struct ngx_as_lib_upcall_s ngx_as_lib_upcall_t;

struct ngx_as_lib_api_s {
    ngx_as_lib_api_t* (*get_api_from_req)(ngx_http_request_t* r);
    int64_t           (*get_loc_id_from_req)(ngx_http_request_t* r);

    ngx_as_lib_upcall_t* (*get_upcall)(void);
    void                 (*set_upcall)(ngx_as_lib_upcall_t* upcall);

    void       (*log)(uintptr_t level, const char* content);
    void       (*notify)(void);
    // h = (ngx_http_request_t*)->ngx_int_t
    intptr_t   (*add_http_handler)(ngx_conf_t* cf, intptr_t phase, ngx_http_handler_pt h);
    void*      (*pcalloc)(ngx_pool_t* pool, size_t size);
    intptr_t   (*http_read_client_request_body)(ngx_http_request_t* r, ngx_http_client_body_handler_pt h);
    intptr_t   (*http_send_header)(ngx_http_request_t* r);
    intptr_t   (*http_buf_output_filter)(ngx_http_request_t* r, ngx_buf_t* buf);
    void       (*http_finalize_request)(ngx_http_request_t* r, intptr_t code);
    intptr_t   (*add_http_header)(ngx_http_request_t* r, ngx_list_t* headers, const char* key, const char* value);

    ngx_http_request_t* (*new_http_dummy_request)(intptr_t server_id);
    void       (*http_run_posted_requests)(ngx_connection_t* c);
    intptr_t   (*http_subrequest)(ngx_http_request_t* r, intptr_t method,
                                  char* uri, char* args, ngx_buf_t* body,
                                  ngx_http_init_subrequest_t* is,
                                  ngx_http_post_subrequest_t* cb);

    int32_t (*main)(int32_t argc, char** argv);
    int32_t (*main_new_thread)(pthread_t* t, int32_t argc, char** argv);
};

typedef struct {
    ngx_int_t         id;
    ngx_as_lib_api_t* api;
} ngx_as_lib_http_loc_conf_t;

ngx_as_lib_api_t* libngx(void);

#endif // _NGX_AS_LIB_MODULE_H_
