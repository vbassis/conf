vcl 4.0;

import std;
import directors;

# Default backend definition. Set this to point to your content server.
backend ap1 {
  .host = "172.31.0.215";
  .port = "8081";
  .first_byte_timeout = 200s;
  .probe = {
         .url = "/";
         .interval = 5s;
         .timeout = 1 s;
         .window = 5;
         .threshold = 3;
         .initial = 1;
  }
}
backend ap2 {
  .host = "172.31.0.215";
  .port = "8082";
  .first_byte_timeout = 200s;
  .probe = {
         .url = "/";
         .interval = 5s;
         .timeout = 1 s;
         .window = 5;
         .threshold = 3;
         .initial = 1;
  }
}
acl purge_ip {
    "localhost";
    "127.0.0.1";
    // ""
}

sub vcl_init{
    new ws = directors.random();
    ws.add_backend(ap1, 1.0);
    ws.add_backend(ap2, 1.0);
}

sub vcl_recv {
    # Happens before we check if we have this in cache already.
    #
    # Typically you clean up the request here, removing cookies you don't need,
    # rewriting the request, etc.

#     std.log("vcl recv: "+req.request);

    if (req.restarts == 0) {
      if (req.http.x-forwarded-for) {
          set req.http.X-Forwarded-For =
          req.http.X-Forwarded-For + ", " + client.ip;
      } else {
          set req.http.X-Forwarded-For = client.ip;
      }
    }
    set req.backend_hint = ws.backend();
    if (req.method != "GET" &&
      req.method != "HEAD" &&
      req.method != "PUT" &&
      req.method != "POST" &&
      req.method != "TRACE" &&
      req.method != "OPTIONS" &&
      req.method != "PURGE" &&
      req.method != "DELETE") {
        /* Non-RFC2616 or CONNECT which is weird. */
        return (pipe);
    }
    if (req.method == "PURGE") {
         if (!client.ip ~ purge_ip) {
             #return(synth(405, "Not Found"));
             return(synth(403, "Not allowed"));
         }
         return (purge);
    }
    if (req.method != "GET" && req.method != "HEAD") {
        /* We only deal with GET and HEAD by default */
        return (pipe);
    }
    if (req.url ~ "\.(jpe?g|png|gif|pdf|gz|tgz|bz2|tbz|tar|zip|tiff|tif)$" || req.url ~ "/(image|(image_(?:[^/]|(?!view.*).+)))$") {
        return (hash);
    }
    if (req.url ~ "\.(svg|swf|ico|mp3|mp4|m4a|ogg|mov|avi|wmv|flv)$") {
        return (hash);
    }
    if (req.url ~ "\.(xls|vsd|doc|ppt|pps|vsd|doc|ppt|pps|xls|pdf|sxw|rar|odc|odb|odf|odg|odi|odp|ods|odt|sxc|sxd|sxi|sxw|dmg|torrent|deb|msi|iso|rpm)$") {
        return (hash);
    }
    if (req.url ~ "\.(css|js)$") {
        return (hash);
    }
    if (req.http.Authorization || req.http.Cookie ~ "(^|; )(__ac=|_ZopeId=)") {
        /* Not cacheable by default */
        return (pipe);
    }
    return (hash);
}

sub vcl_hash {
    hash_data(req.url);
    #if (req.http.host) {
    #    hash_data(req.http.host);
    #} else {
    #    hash_data(server.ip);
    #}
    return (lookup);
}

sub vcl_backend_response {
    # Happens after we have read the response headers from the backend.
    #
    # Here you clean the response headers, removing silly Set-Cookie headers
    # and other mistakes your backend does.
    if (beresp.ttl <= 0s ||
        beresp.http.Set-Cookie ||
        beresp.http.Vary == "*") {
        /*
         * Mark as "Hit-For-Pass" for the next 60 minutes - 24 hours
         */
        if (bereq.url ~ "\.(jpe?g|png|gif|pdf|gz|tgz|bz2|tbz|tar|zip|tiff|tif)$" || bereq.url ~ "/(image|(image_(?:[^/]|(?!view.*).+)))$") {
            set beresp.ttl = std.duration(beresp.http.age+"s",0s) + 6h;
        } elseif (bereq.url ~ "\.(svg|swf|ico|mp3|mp4|m4a|ogg|mov|avi|wmv|flv)$") {
            set beresp.ttl = std.duration(beresp.http.age+"s",0s) + 6h;
        } elseif (bereq.url ~ "\.(xls|vsd|doc|ppt|pps|vsd|doc|ppt|pps|xls|pdf|sxw|rar|odc|odb|odf|odg|odi|odp|ods|odt|sxc|sxd|sxi|sxw|dmg|torrent|deb|msi|iso|rpm)$") {
            set beresp.ttl = std.duration(beresp.http.age+"s",0s) + 6h;
        } elseif (bereq.url ~ "\.(css|js)$") {
            set beresp.ttl = std.duration(beresp.http.age+"s",0s) + 24h;
        } else {
            set beresp.ttl = std.duration(beresp.http.age+"s",0s) + 1h;
        }
    }
    return (deliver);
}

sub vcl_deliver {
    # Happens when we have all the pieces we need, and are about to send the
    # response to the client.
    #
    # You can do accounting or modifying the final object here.
}

sub vcl_synth {
    set resp.http.Content-Type = "text/html; charset=utf-8";
    set resp.http.Retry-After = "5";
    synthetic ("Error");
    return (deliver);
}
