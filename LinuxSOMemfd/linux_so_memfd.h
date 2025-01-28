#ifndef _linux_so_memfd_h_
#define _linux_so_memfd_h_

#define _GNU_SOURCE
#include <inttypes.h>

int ngx_helper_create_memfd_for_so(void* content, uint32_t content_len, const char* dummy_path, char* out_path);

#endif // _linux_so_memfd_h_
