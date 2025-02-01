#ifndef _NGX_AS_LIB_MODULE_H_
#define _NGX_AS_LIB_MODULE_H_

#include <inttypes.h>
#include <time.h>
#include <stddef.h>
#include <stdbool.h>
#include <pthread.h>
#include <sys/socket.h>

#define  NGX_OK          (0)
#define  NGX_ERROR      (-1)
#define  NGX_AGAIN      (-2)
#define  NGX_BUSY       (-3)
#define  NGX_DONE       (-4)
#define  NGX_DECLINED   (-5)
#define  NGX_ABORT      (-6)

#define NGX_HTTP_LC_HEADER_LEN    (32)
#define NGX_HTTP_SPECIAL_RESPONSE (300)

#define NGX_LOG_STDERR            (0)
#define NGX_LOG_EMERG             (1)
#define NGX_LOG_ALERT             (2)
#define NGX_LOG_CRIT              (3)
#define NGX_LOG_ERR               (4)
#define NGX_LOG_WARN              (5)
#define NGX_LOG_NOTICE            (6)
#define NGX_LOG_INFO              (7)
#define NGX_LOG_DEBUG             (8)

#define NGX_HTTP_UNKNOWN                   (0x00000001)
#define NGX_HTTP_GET                       (0x00000002)
#define NGX_HTTP_HEAD                      (0x00000004)
#define NGX_HTTP_POST                      (0x00000008)
#define NGX_HTTP_PUT                       (0x00000010)
#define NGX_HTTP_DELETE                    (0x00000020)
#define NGX_HTTP_MKCOL                     (0x00000040)
#define NGX_HTTP_COPY                      (0x00000080)
#define NGX_HTTP_MOVE                      (0x00000100)
#define NGX_HTTP_OPTIONS                   (0x00000200)
#define NGX_HTTP_PROPFIND                  (0x00000400)
#define NGX_HTTP_PROPPATCH                 (0x00000800)
#define NGX_HTTP_LOCK                      (0x00001000)
#define NGX_HTTP_UNLOCK                    (0x00002000)
#define NGX_HTTP_PATCH                     (0x00004000)
#define NGX_HTTP_TRACE                     (0x00008000)
#define NGX_HTTP_CONNECT                   (0x00010000)

#define NGX_HTTP_POST_READ_PHASE      (0)
#define NGX_HTTP_SERVER_REWRITE_PHASE (1)
#define NGX_HTTP_FIND_CONFIG_PHASE    (2)
#define NGX_HTTP_REWRITE_PHASE        (3)
#define NGX_HTTP_POST_REWRITE_PHASE   (4)
#define NGX_HTTP_PREACCESS_PHASE      (5)
#define NGX_HTTP_ACCESS_PHASE         (6)
#define NGX_HTTP_POST_ACCESS_PHASE    (7)
#define NGX_HTTP_PRECONTENT_PHASE     (8)
#define NGX_HTTP_CONTENT_PHASE        (9)
#define NGX_HTTP_LOG_PHASE           (10)

struct ngx_log_s;
struct ngx_cycle_s;
struct ngx_conf_s;
struct ngx_http_request_s;
struct ngx_pool_s;
struct ngx_buf_s;
struct ngx_str_s;
struct ngx_chain_s;
struct ngx_list_s;
struct ngx_list_part_s;
struct ngx_table_elt_s;
struct ngx_connection_s;
struct ngx_peer_connection_s;
struct ngx_http_init_subrequest_s;
struct ngx_http_post_subrequest_s;

typedef struct ngx_log_s             ngx_log_t;
typedef struct ngx_cycle_s           ngx_cycle_t;
typedef struct ngx_conf_s            ngx_conf_t;
typedef struct ngx_http_request_s    ngx_http_request_t;
typedef struct ngx_pool_s            ngx_pool_t;
typedef struct ngx_buf_s             ngx_buf_t;
typedef struct ngx_str_s             ngx_str_t;
typedef struct ngx_chain_s           ngx_chain_t;
typedef struct ngx_connection_s      ngx_connection_t;
typedef struct ngx_peer_connection_s ngx_peer_connection_t;

typedef struct ngx_http_init_subrequest_s ngx_http_init_subrequest_t;
typedef struct ngx_http_post_subrequest_s ngx_http_post_subrequest_t;

typedef struct ngx_list_s         ngx_list_t;
typedef struct ngx_list_part_s    ngx_list_part_t;
typedef struct ngx_table_elt_s    ngx_table_elt_t;

typedef int64_t off_t;
typedef void* ngx_buf_tag_t;
typedef uintptr_t ngx_msec_t;

typedef intptr_t (*ngx_http_handler_pt)(ngx_http_request_t*);
typedef void     (*ngx_http_client_body_handler_pt)(ngx_http_request_t*);
typedef intptr_t (*ngx_http_init_subrequest_pt)(ngx_http_request_t *r, void *data);
typedef intptr_t (*ngx_http_post_subrequest_pt)(ngx_http_request_t *r, void *data, intptr_t rc);
typedef int32_t  (*loop_func_t)(void *arg);

struct ngx_as_lib_api_s;
typedef struct ngx_as_lib_api_s ngx_as_lib_api_t;

struct ngx_as_lib_upcall_s {
    void* ud;

    int64_t (*looptick)(ngx_as_lib_api_t* api, void* ud);

    // core
    intptr_t (*init_master) (ngx_as_lib_api_t* api, void* ud, ngx_log_t* log);
    intptr_t (*init_module) (ngx_as_lib_api_t* api, void* ud, ngx_cycle_t* cycle);
    intptr_t (*init_process)(ngx_as_lib_api_t* api, void* ud, ngx_cycle_t* cycle);
    intptr_t (*init_thread) (ngx_as_lib_api_t* api, void* ud, ngx_cycle_t* cycle);
    void     (*exit_thread) (ngx_as_lib_api_t* api, void* ud, ngx_cycle_t* cycle);
    void     (*exit_process)(ngx_as_lib_api_t* api, void* ud, ngx_cycle_t* cycle);
    void     (*exit_master) (ngx_as_lib_api_t* api, void* ud, ngx_cycle_t* cycle);

    // http
    intptr_t(*postconfiguration)(ngx_as_lib_api_t* api, void* ud, ngx_conf_t* cf);
    intptr_t(*get_upstream_peer)(ngx_as_lib_api_t* api, void* ud, ngx_http_request_t* r, uintptr_t id, ngx_peer_connection_t* pc);
};
typedef struct ngx_as_lib_upcall_s ngx_as_lib_upcall_t;

struct ngx_as_lib_api_s {
    ngx_as_lib_api_t* (*get_api_from_req)(ngx_http_request_t* r);
    int64_t           (*get_loc_id_from_req)(ngx_http_request_t* r);

    ngx_as_lib_upcall_t* (*get_upcall)(void);
    void                 (*set_upcall)(ngx_as_lib_upcall_t* upcall);

    void       (*log)(uintptr_t level, const char* content);
    void       (*notify)(void);
    // h = (ngx_http_request_t*)->intptr_t
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
    int32_t (*main_new_thread)(pthread_t* t, ngx_as_lib_api_t* main_api, int32_t argc, char** argv, bool is_primary, uint32_t cid, uint32_t worker_id);
    void    (*ff_reg_worker_job)(uint32_t cid, loop_func_t f, void* arg);
};

#if (NGX_AS_LIB_WITH_DLOPEN)
#define LIBNGX "libngx"
typedef ngx_as_lib_api_t*(*libngx_entrypoint)(void);
#else
ngx_as_lib_api_t* libngx(void);
#endif

// redefine nginx structs

struct ngx_str_s {
    size_t len;
    void*  data;
};

struct ngx_list_part_s {
    void*            elts;
    uintptr_t        nelts;
    ngx_list_part_t* next;
};

struct ngx_list_s {
    ngx_list_part_t*  last;
    ngx_list_part_t   part;
    size_t            size;
    uintptr_t         nalloc;
    ngx_pool_t*       pool;
};

struct ngx_table_elt_s {
    uintptr_t        hash;
    ngx_str_t        key;
    ngx_str_t        value;
    char*            lowcase_key;
    ngx_table_elt_t* next;
};

struct ngx_chain_s {
    ngx_buf_t*   buf;
    ngx_chain_t* next;
};

struct ngx_buf_s {
    void*         pos;
    void*         last;
    off_t         file_pos;
    off_t         file_last;

    void*         start;
    void*         end;
    ngx_buf_tag_t tag;
    void*         file; // ngx_file_t
    ngx_buf_t*    shadow;

#define NGX_BUF_temporary     (0b000000000001)
#define NGX_BUF_memory        (0b000000000010)
#define NGX_BUF_mmap          (0b000000000100)
#define NGX_BUF_recycled      (0b000000001000)
#define NGX_BUF_in_file       (0b000000010000)
#define NGX_BUF_flush         (0b000000100000)
#define NGX_BUF_sync          (0b000001000000)
#define NGX_BUF_last_buf      (0b000010000000)
#define NGX_BUF_last_in_chain (0b000100000000)
#define NGX_BUF_last_shadow   (0b001000000000)
#define NGX_BUF_temp_file     (0b010000000000)
    uint32_t flags;

    int32_t num;
};

struct ngx_http_init_subrequest_s {
    ngx_http_init_subrequest_pt handler;
    void*                       data;
};
struct ngx_http_post_subrequest_s {
    ngx_http_post_subrequest_pt handler;
    void*                       data;
};

typedef struct {
    ngx_list_t                        headers;

    ngx_table_elt_t*                  host;
    ngx_table_elt_t*                  connection;
    ngx_table_elt_t*                  if_modified_since;
    ngx_table_elt_t*                  if_unmodified_since;
    ngx_table_elt_t*                  if_match;
    ngx_table_elt_t*                  if_none_match;
    ngx_table_elt_t*                  user_agent;
    ngx_table_elt_t*                  referer;
    ngx_table_elt_t*                  content_length;
    ngx_table_elt_t*                  content_range;
    ngx_table_elt_t*                  content_type;

    ngx_table_elt_t*                  range;
    ngx_table_elt_t*                  if_range;

    ngx_table_elt_t*                  transfer_encoding;
    ngx_table_elt_t*                  te;
    ngx_table_elt_t*                  expect;
    ngx_table_elt_t*                  upgrade;

// NGX_HTTP_GZIP || NGX_HTTP_HEADERS
    ngx_table_elt_t                  *accept_encoding;
    ngx_table_elt_t                  *via;
// ---

    ngx_table_elt_t*                  authorization;

    ngx_table_elt_t*                  keep_alive;

// NGX_HTTP_X_FORWARDED_FOR
    ngx_table_elt_t                  *x_forwarded_for;
// ---

// NGX_HTTP_REALIP
    ngx_table_elt_t                  *x_real_ip;
// ---

// NGX_HTTP_HEADERS
    ngx_table_elt_t                  *accept;
    ngx_table_elt_t                  *accept_language;
// ---

// NGX_HTTP_DAV
    ngx_table_elt_t                  *depth;
    ngx_table_elt_t                  *destination;
    ngx_table_elt_t                  *overwrite;
    ngx_table_elt_t                  *date;
// ---

    ngx_table_elt_t*                  cookie;

    ngx_str_t                         user;
    ngx_str_t                         passwd;

    ngx_str_t                         server;
    off_t                             content_length_n;
    time_t                            keep_alive_n;

    uint32_t: 32;
} ngx_http_headers_in_t;

typedef struct {
    ngx_list_t                        headers;
    ngx_list_t                        trailers;

    uintptr_t                         status;
    ngx_str_t                         status_line;

    ngx_table_elt_t*                  server;
    ngx_table_elt_t*                  date;
    ngx_table_elt_t*                  content_length;
    ngx_table_elt_t*                  content_encoding;
    ngx_table_elt_t*                  location;
    ngx_table_elt_t*                  refresh;
    ngx_table_elt_t*                  last_modified;
    ngx_table_elt_t*                  content_range;
    ngx_table_elt_t*                  accept_ranges;
    ngx_table_elt_t*                  www_authenticate;
    ngx_table_elt_t*                  expires;
    ngx_table_elt_t*                  etag;

    ngx_table_elt_t*                  cache_control;
    ngx_table_elt_t*                  link;

    ngx_str_t*                        override_charset;

    size_t                            content_type_len;
    ngx_str_t                         content_type;
    ngx_str_t                         charset;
    char*                             content_type_lowcase;
    uintptr_t                         content_type_hash;

    off_t                             content_length_n;
    off_t                             content_offset;
    time_t                            date_time;
    time_t                            last_modified_time;
} ngx_http_headers_out_t;

typedef struct {
    void*                             temp_file; // ngx_temp_file_t
    ngx_chain_t*                      bufs;
    ngx_buf_t*                        buf;
    off_t                             rest;
    off_t                             received;
    ngx_chain_t*                      free;
    ngx_chain_t*                      busy;
    void*                             chunked; // ngx_http_chunked_t
    void*                             post_handler; // ngx_http_client_body_handler_pt
} ngx_http_request_body_t;

struct ngx_http_request_s {
    uint32_t                          signature;         /* "HTTP" */

    void*                             data; /* user data */
    bool                              is_dummy;

    ngx_connection_t*                 connection;

    void**                            ctx;
    void**                            main_conf;
    void**                            srv_conf;
    void**                            loc_conf;

    void*                             read_event_handler; // ngx_http_event_handler_pt
    void*                             write_event_handler; // ngx_http_event_handler_pt

    void*                             upstream; // ngx_http_upstream_t
    void*                             upstream_states; // ngx_array_t
                                         /* of ngx_http_upstream_state_t */

    ngx_pool_t*                       pool;
    ngx_buf_t*                        header_in;

    ngx_http_headers_in_t             headers_in;
    ngx_http_headers_out_t            headers_out;

    ngx_http_request_body_t*          request_body;

    time_t                            lingering_time;
    time_t                            start_sec;
    ngx_msec_t                        start_msec;

    uintptr_t                         method;
    uintptr_t                         http_version;

    ngx_str_t                         request_line;
    ngx_str_t                         uri;
    ngx_str_t                         args;
    ngx_str_t                         exten;
    ngx_str_t                         unparsed_uri;

    ngx_str_t                         method_name;
    ngx_str_t                         http_protocol;
    ngx_str_t                         schema;

    ngx_chain_t*                      out;
    ngx_http_request_t*               main;
    ngx_http_request_t*               parent;
    void*                             postponed; // ngx_http_postponed_request_t
    void*                             post_subrequest; // ngx_http_post_subrequest_t
    void*                             posted_requests; // ngx_http_posted_request_t

    intptr_t                          phase_handler;
    void*                             content_handler; // ngx_http_handler_pt
    uintptr_t                         access_code;

    void*                             variables; // ngx_http_variable_value_t

    size_t                            limit_rate;
    size_t                            limit_rate_after;

    /* used to learn the Apache compatible response length without a header */
    size_t                            header_size;

    off_t                             request_length;

    uintptr_t                         err_status;

    void*                             http_connection; // ngx_http_connection_t
    void*                             stream; // ngx_http_v2_stream_t
    void*                             v3_parse; // ngx_http_v3_parse_t

    void*                             log_handler; // ngx_http_log_handler_pt

    void*                             cleanup; // ngx_http_cleanup_t

    /* used to parse HTTP headers */

    uintptr_t                         state;

    uintptr_t                         header_hash;
    uintptr_t                         lowcase_index;
    char                              lowcase_header[NGX_HTTP_LC_HEADER_LEN];

    char*                             header_name_start;
    char*                             header_name_end;
    char*                             header_start;
    char*                             header_end;

    /*
     * a memory that can be reused after parsing a request line
     * via ngx_http_ephemeral_t
     */

    char*                             uri_start;
    char*                             uri_end;
    char*                             uri_ext;
    char*                             args_start;
    char*                             request_start;
    char*                             request_end;
    char*                             method_end;
    char*                             schema_start;
    char*                             schema_end;
    char*                             host_start;
    char*                             host_end;

    ngx_buf_t                         appbuf;

    uint16_t                          http_minor;
    uint16_t                          http_major;

    uint16_t                          count;
    bool                              header_only;
};

struct ngx_peer_connection_s {
    ngx_connection_t* connection;
    struct sockaddr*  sockaddr;
    socklen_t         socklen;
    ngx_str_t*        name;
};

#endif // _NGX_AS_LIB_MODULE_H_
