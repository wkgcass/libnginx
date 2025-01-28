#include <ngx_as_lib_module.h>
#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#include <netinet/in.h>
#include <arpa/inet.h>

struct sample_data {
    char* data;
    int   len;
};

static char no_data_str[] = "no data\n";

#define $return(n) \
    api->http_finalize_request(r, n); \
    return;

void sample_body_handler(ngx_http_request_t* r) {
    ngx_as_lib_api_t*  api = libngx()->get_api_from_req(r);
    struct sample_data* ud = api->get_upcall()->ud;
    if (r->method & NGX_HTTP_GET) {
        if (ud->data) {
            ngx_buf_t* buf = &r->appbuf;
            char* data = api->pcalloc(r->pool, ud->len);
            if (!buf || !data) {
                $return(500);
            }
            memcpy(data, ud->data, ud->len);
            r->headers_out.status = 200;
            r->headers_out.content_length_n = ud->len;
            if (!ud->len) {
                r->header_only = 1;
            }
            int err = api->http_send_header(r);
            if (err) { $return(err); }

            buf->pos  = (void*)data;
            buf->last = (void*)data + ud->len;
            buf->flags |= NGX_BUF_temporary;
            if (r->header_only) {
                $return(0);
            }
            buf->flags |= NGX_BUF_last_buf;
            $return(api->http_buf_output_filter(r, buf));
        } else {
            ngx_buf_t* buf = &r->appbuf;
            if (!buf) {
                $return(500);
            }
            r->headers_out.status = 404;
            r->headers_out.content_length_n = strlen(no_data_str);
            int err = api->http_send_header(r);
            if (err) { $return(err); }

            buf->pos  = (void*)no_data_str;
            buf->last = (void*)no_data_str + strlen(no_data_str);
            buf->flags |= NGX_BUF_memory;
            buf->flags |= NGX_BUF_last_buf;
            $return(api->http_buf_output_filter(r, buf));
        }
    } else if (r->method & NGX_HTTP_POST) {
        if (!r->request_body || !r->request_body->bufs) {
            $return(500);
        }

        ngx_chain_t* chain = r->request_body->bufs;
        if (chain->next) {
            $return(500);
        }
        int len = chain->buf->last - chain->buf->pos;
        char* new_data = malloc(len+1);
        memcpy(new_data, chain->buf->pos, len);
        new_data[len] = '\0';
        if (ud->data) {
            free(ud->data);
        }
        ud->data = new_data;
        ud->len = len;

        r->headers_out.status = 200;
        r->headers_out.content_length_n = 0;
        r->header_only = 1;
        int err = api->http_send_header(r);
        if (err) {
            $return(err);
        }
        $return(0);
    } else {
        $return(405);
    }
}

intptr_t sample_handler(ngx_http_request_t* r) {
    ngx_as_lib_api_t* api = libngx()->get_api_from_req(r);
    int err = api->http_read_client_request_body(r, sample_body_handler);
    if (err >= NGX_HTTP_SPECIAL_RESPONSE) {
        return err;
    }
    return NGX_DONE;
}

intptr_t sample_postconfiguration(ngx_as_lib_api_t* api, void* ud, ngx_conf_t* cf) {
    return api->add_http_handler(cf, NGX_HTTP_CONTENT_PHASE, sample_handler);
}

intptr_t sample_get_upstream_peer(ngx_as_lib_api_t* api, void* ud, ngx_http_request_t* r,
  uintptr_t id, ngx_peer_connection_t* pc) {
    struct sockaddr_in* sockaddr = api->pcalloc(r->pool, sizeof(struct sockaddr_in));
    sockaddr->sin_family = AF_INET;
    inet_pton(AF_INET, "127.0.0.1", &sockaddr->sin_addr);
    sockaddr->sin_port = htons(8899);
    pc->sockaddr = (void*)sockaddr;
    pc->socklen = sizeof(*sockaddr);
    return NGX_OK;
}

int64_t sample_looptick(ngx_as_lib_api_t* api, void* _ud) {
    struct sample_data* ud = _ud;
    char log[256];
    sprintf(log, "loop tick triggered, data=%s", ud->data);
    api->log(NGX_LOG_INFO, log);
    return -1;
}

int main(int argc, char** argv) {
    struct sample_data data = { 0 };
    ngx_as_lib_upcall_t upcall = {
        .ud = &data,
        .looptick = sample_looptick,
        .postconfiguration = sample_postconfiguration,
        .get_upstream_peer = sample_get_upstream_peer,
    };

    libngx()->set_upcall(&upcall);
    return libngx()->main(argc, argv);
}
