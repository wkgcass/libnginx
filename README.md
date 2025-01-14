<picture>
  <source media="(prefers-color-scheme: dark)" srcset="https://github.com/user-attachments/assets/9335b488-ffcc-4157-8364-2370a0b70ad0">
  <source media="(prefers-color-scheme: light)" srcset="https://github.com/user-attachments/assets/3a7eeb08-1133-47f5-859c-fad4f5a6a013">
  <img alt="NGINX Banner">
</picture>

---

## Build as Lib

```bash
auto/configure \
	--with-http_ssl_module        \
	--with-http_v2_module         \
	--with-http_v3_module         \
	--with-ngx_as_lib
# You may add `--without-http_rewrite_module` if you don't have PCRE library.

make
make sample
```

> Any statically linked module should work fine when compiling with `--with-ngx_as_lib`.  
> It would be fine if any module depends on a shared library,  
> but the module itself should not be a shared library.

You can find the following results:

* `objs/libnginx.so` or `objs/libnginx.dylib`
* `sample/sample`

## Run the sample

```bash
LD_LIBRARY_PATH=`pwd`/objs ./sample/sample -c `pwd`/sample/sample.conf

# another shell
curl 127.0.0.1:7788/sample
curl 127.0.0.1:7788/sample --data 'hello'
curl 127.0.0.1:7788/sample
```

## How to use

#### 1. load libnginx

Use `dlopen` to load `libnginx.so` or `libnginx.dylib`.  
You must **copy** the shared library file, and load **one** for **each** worker thread.

Retrieve `api` from the lib:

```c
libngx_entrypoint* f = dlsym(lib, LIBNGX);
ngx_as_lib_api_t* api = f();
```

You may save the first retrieved `api` to a global variable, maybe called `baseApi`.  
The only safe api to be invoked on `baseApi` is `get_api_from_req`.

#### 2. prepare the `ngx_as_lib_upcall_t` object

```c
ngx_as_lib_upcall_t* upcall = malloc(sizeof(ngx_as_lib_upcall_t));
memset(upcall, 0, sizeof(*upcall));

upcall->ud =                /* user data */ data;
upcall->postconfiguration = /* the postconfiguration callback */ postconfiguration;

// optional fields:
upcall->looptick;      // called for each nginx loop
upcall->init_master;   // the init_master callback
upcall->init_module;   // the init_module callback
upcall->init_process;  // the init_process callback
upcall->init_thread;   // the init_thread callback
upcall->exit_thread;   // the exit_thread callback
upcall->exit_process;  // the exit_process callback
upcall->exit_master;   // the exit_master callback
// though theses callbacks are provided, some of them would never be called
// since the nginx instances are launched with `master_process off` implicitly
```

#### 3. implement callbacks

The most important callback is `postconfiguration`, you may register an http handler to the config:

```c
intptr_t postconfiguration(ngx_as_lib_api_t* api, void* ud, ngx_conf_t* cf) {
    return api->add_http_handler(cf, NGX_HTTP_CONTENT_PHASE, handler);
}
```

The `handler` is the http handler registered into the nginx configuration structure.  
Usually you would need the http body from the http request, so you can implement as the follow:

```c
intptr_t sample_handler(ngx_http_request_t* r) {
    ngx_as_lib_api_t* api = baseApi->get_api_from_req(r);
    int err = api->http_read_client_request_body(r, body_handler);
    if (err >= NGX_HTTP_SPECIAL_RESPONSE) {
        return err;
    }
    return NGX_DONE;
}
```

In the `body_handler`, you can retrieve request body from `r->request_body`.

* Call `api->http_send_header(r)` to send http headers (though they may not be directed flushed to client).
* Call `api->http_buf_output_filter(r, buf)` to send the buf as http payload.
* Call `api->http_finalize_request(r, code)` when you finished processing the request.

You may refer to the `sample/main.c` about how to implement a simple http server based on nginx base code and above apis.

#### 4. set the upcall

```c
api->set_upcall(upcall);
```

#### 5. spawn the worker thread

```c
pthread_t thread;
int err = api->main_new_thread(&thread, argc, argv);
if (err) {
    goto errout;
}
pthread_join(thread, NULL);
```

The `argc` and `argv` are the same as those would be passed to a normal nginx program, such as:

* `nginx`
* `-c`
* `/etc/nginx/nginx.conf`

## Swift support

You can use this library with `Swift`.

#### sample

```bash
swift run sample --threads=4
```

#### how to use

```swift
let package = Package(
    // ...
    dependencies: [
        .package(url: "https://github.com/wkgcass/libnginx", branch: "libnginx"),
    ]
    // ...
)
```

```swift
import ngx_swift

let app = App(libpath: "libnginx.so")
app.threads = [AppThreadConf](repeating: AppThreadConf(), count: 4)

app.addHttpServerHandler(id: 1) { req in
    req.status(200)
    return try req.end("I am upcall 1\r\n")
}
app.addHttpServerHandler(id: 2) { req in
    req.status(200)
    return try req.end("I am upcall 2\r\n")
}
try app.launch(conf: """
events {}
http {
    server {
        listen 0.0.0.0:7788 reuseport;
        location = /a {
            upcall 1;
        }
        location = /b {
            upcall 2;
        }
    }
}
""")
// should block forever
```

---

NGINX (pronounced "engine x" or "en-jin-eks") is the world's most popular Web Server, high performance Load Balancer, Reverse Proxy, API Gateway and Content Cache.

NGINX is free and open source software, distributed under the terms of a simplified [2-clause BSD-like license](LICENSE).

Enterprise distributions, commercial support and training are available from [F5, Inc](https://www.f5.com/products/nginx).

> [!IMPORTANT]
> The goal of this README is to provide a basic, structured introduction to NGINX for novice users. Please refer to the [full NGINX documentation](https://nginx.org/en/docs/) for detailed information on [installing](https://nginx.org/en/docs/install.html), [building](https://nginx.org/en/docs/configure.html), [configuring](https://nginx.org/en/docs/dirindex.html), [debugging](https://nginx.org/en/docs/debugging_log.html), and more. These documentation pages also contain a more detailed [Beginners Guide](https://nginx.org/en/docs/beginners_guide.html), How-Tos, [Development guide](https://nginx.org/en/docs/dev/development_guide.html), and a complete module and [directive reference](https://nginx.org/en/docs/dirindex.html).

# Table of contents
- [How it works](#how-it-works)
  - [Modules](#modules)
  - [Configurations](#configurations)
  - [Runtime](#runtime)
- [Downloading and installing](#downloading-and-installing)
  - [Stable and Mainline binaries](#stable-and-mainline-binaries)
  - [Linux binary installation process](#linux-binary-installation-process)
  - [FreeBSD installation process](#freebsd-installation-process)
  - [Windows executables](#windows-executables)
  - [Dynamic modules](#dynamic-modules)
- [Getting started with NGINX](#getting-started-with-nginx)
  - [Installing SSL certificates and enabling TLS encryption](#installing-ssl-certificates-and-enabling-tls-encryption)
  - [Load Balancing](#load-balancing)
  - [Rate limiting](#rate-limiting)
  - [Content caching](#content-caching)
- [Building from source](#building-from-source)
  - [Installing dependencies](#installing-dependencies)
  - [Cloning the NGINX GitHub repository](#cloning-the-nginx-github-repository)
  - [Configuring the build](#configuring-the-build)
  - [Compiling](#compiling)
  - [Location of binary and installation](#location-of-binary-and-installation)
  - [Running and testing the installed binary](#running-and-testing-the-installed-binary)
- [Asking questions and reporting issues](#asking-questions-and-reporting-issues)
- [Contributing code](#contributing-code)
- [Additional help and resources](#additional-help-and-resources)
- [Changelog](#changelog)
- [License](#license)

# How it works
NGINX is installed software with binary packages available for all major operating systems and Linux distributions. See [Tested OS and Platforms](https://nginx.org/en/#tested_os_and_platforms) for a full list of compatible systems.

> [!IMPORTANT]
> While nearly all popular Linux-based operating systems are distributed with a community version of nginx, we highly advise installation and usage of official [packages](https://nginx.org/en/linux_packages.html) or sources from this repository. Doing so ensures that you're using the most recent release or source code, including the latest feature-set, fixes and security patches.

## Modules
NGINX is comprised of individual modules, each extending core functionality by providing additional, configurable features. See "Modules reference" at the bottom of [nginx documentation](https://nginx.org/en/docs/) for a complete list of official modules.

NGINX modules can be built and distributed as static or dynamic modules. Static modules are defined at build-time, compiled, and distributed in the resulting binaries. See [Dynamic Modules](#dynamic-modules) for more information on how they work, as well as, how to obtain, install, and configure them.

> [!TIP]
> You can issue the following command to see which static modules your NGINX binaries were built with:
```bash
nginx -V
```
> See [Configuring the build](#configuring-the-build) for information on how to include specific Static modules into your nginx build.


## Configurations
NGINX is highly flexible and configurable. Provisioning the software is achieved via text-based config file(s) accepting parameters called "[Directives](https://nginx.org/en/docs/dirindex.html)". See [Configuration File's Structure](https://nginx.org/en/docs/beginners_guide.html#conf_structure) for a comprehensive description of how NGINX configuration files work.

> [!NOTE]
> The set of directives available to your distribution of NGINX is dependent on which [modules](#modules) have been made available to it.

## Runtime
Rather than running in a single, monolithic process, NGINX is architected to scale beyond Operating System process limitations by operating as a collection of processes. They include:
- A "master" process that maintains worker processes, as well as, reads and evaluates configuration files.
- One or more "worker" processes that process data (eg. HTTP requests).

The number of [worker processes](https://nginx.org/en/docs/ngx_core_module.html#worker_processes) is defined in the configuration file and may be fixed for a given configuration or automatically adjusted to the number of available CPU cores. In most cases, the latter option optimally balances load across available system resources, as NGINX is designed to efficiently distribute work across all worker processes.

> [!TIP]
> Processes synchronize data through shared memory. For this reason, many NGINX directives require the allocation of shared memory zones. As an example, when configuring [rate limiting](https://nginx.org/en/docs/http/ngx_http_limit_req_module.html#limit_req), connecting clients may need to be tracked in a [common memory zone](https://nginx.org/en/docs/http/ngx_http_limit_req_module.html#limit_req_zone) so all worker processes can know how many times a particular client has accessed the server in a span of time.

# Downloading and installing
Follow these steps to download and install precompiled NGINX binaries. You may also choose to [build NGINX locally from source code](#building-from-source).

## Stable and Mainline binaries
NGINX binaries are built and distributed in two versions: stable and mainline. Stable binaries are built from stable branches and only contain critical fixes backported from the mainline version. Mainline binaries are built from the [master branch](https://github.com/nginx/nginx/tree/master) and contain the latest features and bugfixes. You'll need to [decide which is appropriate for your purposes](https://docs.nginx.com/nginx/admin-guide/installing-nginx/installing-nginx-open-source/#choosing-between-a-stable-or-a-mainline-version).

## Linux binary installation process
The NGINX binary installation process takes advantage of package managers native to specific Linux distributions. For this reason, first-time installations involve adding the official NGINX package repository to your system's package manager. Follow [these steps](https://nginx.org/en/linux_packages.html) to download, verify, and install NGINX binaries using the package manager appropriate for your Linux distribution.

### Upgrades
Future upgrades to the latest version can be managed using the same package manager without the need to manually download and verify binaries.

## FreeBSD installation process
For more information on installing NGINX on FreeBSD system, visit https://nginx.org/en/docs/install.html

## Windows executables
Windows executables for mainline and stable releases can be found on the main [NGINX download page](https://nginx.org/en/download.html). Note that the current implementation of NGINX for Windows is at the Proof-of-Concept stage and should only be used for development and testing purposes. For additional information, please see [nginx for Windows](https://nginx.org/en/docs/windows.html).

## Dynamic modules
NGINX version 1.9.11 added support for [Dynamic Modules](https://nginx.org/en/docs/ngx_core_module.html#load_module). Unlike Static modules, dynamically built modules can be downloaded, installed, and configured after the core NGINX binaries have been built. [Official dynamic module binaries](https://nginx.org/en/linux_packages.html#dynmodules) are available from the same package repository as the core NGINX binaries described in previous steps.

> [!TIP]
> [NGINX JavaScript (njs)](https://github.com/nginx/njs), is a popular NGINX dynamic module that enables the extension of core NGINX functionality using familiar JavaScript syntax.

> [!IMPORTANT]
> If desired, dynamic modules can also be built statically into NGINX at compile time.

# Getting started with NGINX
For a gentle introduction to NGINX basics, please see our [Beginner’s Guide](https://nginx.org/en/docs/beginners_guide.html).

## Installing SSL certificates and enabling TLS encryption
See [Configuring HTTPS servers](https://nginx.org/en/docs/http/configuring_https_servers.html) for a quick guide on how to enable secure traffic to your NGINX installation.

## Load Balancing
For a quick start guide on configuring NGINX as a Load Balancer, please see [Using nginx as HTTP load balancer](https://nginx.org/en/docs/http/load_balancing.html).

## Rate limiting
See our [Rate Limiting with NGINX](https://blog.nginx.org/blog/rate-limiting-nginx) blog post for an overview of core concepts for provisioning NGINX as an API Gateway.

## Content caching
See [A Guide to Caching with NGINX and NGINX Plus](https://blog.nginx.org/blog/nginx-caching-guide) blog post for an overview of how to use NGINX as a content cache (e.g. edge server of a content delivery network).

# Building from source
The following steps can be used to build NGINX from source code available in this repository.

## Installing dependencies
Most Linux distributions will require several dependencies to be installed in order to build NGINX. The following instructions are specific to the `apt` package manager, widely available on most Ubuntu/Debian distributions and their derivatives.

> [!TIP]
> It is always a good idea to update your package repository lists prior to installing new packages.
> ```bash
> sudo apt update
> ```

### Installing compiler and make utility
Use the following command to install the GNU C compiler and Make utility.

```bash
sudo apt install gcc make
```

### Installing dependency libraries

```bash
sudo apt install libpcre3-dev zlib1g-dev
```

> [!WARNING]
> This is the minimal set of dependency libraries needed to build NGINX with rewriting and gzip capabilities. Other dependencies may be required if you choose to build NGINX with additional modules. Monitor the output of the `configure` command discussed in the following sections for information on which modules may be missing. For example, if you plan to use SSL certificates to encrypt traffic with TLS, you'll need to install the OpenSSL library. To do so, issue the following command.

>```bash
>sudo apt install libssl-dev

## Cloning the NGINX GitHub repository
Using your preferred method, clone the NGINX repository into your development directory. See [Cloning a GitHub Repository](https://docs.github.com/en/repositories/creating-and-managing-repositories/cloning-a-repository) for additional help.

```bash
git clone https://github.com/nginx/nginx.git
```

## Configuring the build
Prior to building NGINX, you must run the `configure` script with [appropriate flags](https://nginx.org/en/docs/configure.html). This will generate a Makefile in your NGINX source root directory that can then be used to compile NGINX with [options specified during configuration](https://nginx.org/en/docs/configure.html).

From the NGINX source code repository's root directory:

```bash
auto/configure
```

> [!IMPORTANT]
> Configuring the build without any flags will compile NGINX with the default set of options. Please refer to https://nginx.org/en/docs/configure.html for a full list of available build configuration options.

## Compiling
The `configure` script will generate a `Makefile` in the NGINX source root directory upon successful execution. To compile NGINX into a binary, issue the following command from that same directory:

```bash
make
```

## Location of binary and installation
After successful compilation, a binary will be generated at `<NGINX_SRC_ROOT_DIR>/objs/nginx`. To install this binary, issue the following command from the source root directory:

```bash
sudo make install
```

> [!IMPORTANT]
> The binary will be installed into the `/usr/local/nginx/` directory.

## Running and testing the installed binary
To run the installed binary, issue the following command:

```bash
sudo /usr/local/nginx/sbin/nginx
```

You may test NGINX operation using `curl`.

```bash
curl localhost
```

The output of which should start with:

```html
<!DOCTYPE html>
<html>
<head>
<title>Welcome to nginx!</title>
```

# Asking questions and reporting issues
We encourage you to engage with us.
- [NGINX GitHub Discussions](https://github.com/nginx/nginx/discussions), is the go-to place to start asking questions and sharing your thoughts.
- Our [GitHub Issues](https://github.com/nginx/nginx/issues) page offers space to submit and discuss specific issues, report bugs, and suggest enhancements.

# Contributing code
Please see the [Contributing](CONTRIBUTING.md) guide for information on how to contribute code.

# Additional help and resources
- See the [NGINX Community Blog](https://blog.nginx.org/) for more tips, tricks and HOW-TOs related to NGINX and related projects.
- Access [nginx.org](https://nginx.org/), your go-to source for all documentation, information and software related to the NGINX suite of projects.

# Changelog
See our [changelog](https://nginx.org/en/CHANGES) to keep track of updates.

# License
[2-clause BSD-like license](LICENSE)

---
Additional documentation available at: https://nginx.org/en/docs
