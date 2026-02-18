{
  description = "websites setup";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-25.11";
    nixpkgs-unstable.url = "github:nixos/nixpkgs/nixpkgs-unstable";
    colmena.url = "github:zhaofengli/colmena";
  };

  outputs = { self, nixpkgs, colmena, ...}@inputs: let
    pkgs = import nixpkgs {
      system = "x86_64-linux";
    };

    # Helper to create dev shell for a system
    mkDevShell = system: let
      devPkgs = import nixpkgs { inherit system; };
    in devPkgs.mkShell {
      buildInputs = with devPkgs; [
        go
        gopls
        imagemagick
        pkg-config
        zola
        bash
      ];

      shellHook = ''
        export PKG_CONFIG_PATH="${devPkgs.imagemagick}/lib/pkgconfig:$PKG_CONFIG_PATH"
        echo "✓ Development shell loaded"
        echo "  Go: $(go version)"
        echo "  ImageMagick: $(magick -version | head -1)"
        echo ""
        echo "Build cover-crop:"
        echo "  go build -o cover-crop ./cmd/cover-crop"
      '';
    };
  in {
    # Development shells for different platforms
    devShells.aarch64-darwin.default = mkDevShell "aarch64-darwin";
    devShells.x86_64-linux.default = mkDevShell "x86_64-linux";

    colmenaHive = colmena.lib.makeHive {
      meta = {
        nixpkgs = pkgs;
      };

      webserver = { modulesPath, lib, ... }: {
        imports = lib.optional (builtins.pathExists ./do-userdata.nix) ./do-userdata.nix ++ [
          (modulesPath + "/virtualisation/digital-ocean-config.nix")
        ];

        environment.systemPackages = with pkgs; [
          goaccess
        ];

        system.stateVersion = "23.11";

        networking.firewall.allowedTCPPorts = [ 22 80 443 ];

        security.acme = {
          acceptTerms = true;
          defaults.email = "me@joncarl.com";
        };

        services.logrotate.settings.nginx.frequency = "daily";

        services.nginx = {
          enable = true;
          recommendedBrotliSettings = true;
          recommendedGzipSettings = true;
          commonHttpConfig = ''
server {
  listen 80 default_server;
  listen 443 ssl default_server;

  ssl_reject_handshake on;

  return 444;
}
'';
          appendHttpConfig = ''
log_format vcombined '$host:$server_port $remote_addr - $remote_user [$time_local] "$request" $status $body_bytes_sent "$http_referer" "$http_user_agent"';
access_log /var/log/nginx/access.log vcombined;
'';
          virtualHosts = {
            "jonhikes.com" = {
              forceSSL = true;
              enableACME = true;
              root = "/site/jonhikes";
              # default cache of one-day
              extraConfig = ''
expires 1d;
add_header Cache-Control "public";
add_header Strict-Transport-Security "max-age=63072000; includeSubDomains; preload" always;

rewrite ^/glacier-2022-day-9-28f136306bca$ /posts/glacier-2022-day-9 permanent;
rewrite ^/glacier-2022-day-8-95bc86fadb89$ /posts/glacier-2022-day-8 permanent;
rewrite ^/glacier-2022-day-7-fe9611b18cee$ /posts/glacier-2022-day-7 permanent;
rewrite ^/glacier-2022-day-6-8dcb5d01b175$ /posts/glacier-2022-day-6 permanent;
rewrite ^/glacier-2022-day-5-df5c50df0987$ /posts/glacier-2022-day-5 permanent;
rewrite ^/glacier-2022-day-4-937b9d2cd9ce$ /posts/glacier-2022-day-4 permanent;
rewrite ^/glacier-2022-day-3-b32c190703b$ /posts/glacier-2022-day-3 permanent;
rewrite ^/glacier-2022-day-2-88bc47b2f1cc$ /posts/glacier-2022-day-2 permanent;
rewrite ^/glacier-2022-day-1-d502fc01fc43$ /posts/glacier-2022-day-1 permanent;
rewrite ^/glacier-2022-day-0-1dc21adf32f9$ /posts/glacier-2022-day-0 permanent;
rewrite ^/glacier-2022-af4f9139cdc6$ /posts/glacier-2022 permanent;
rewrite ^/why-im-getting-off-the-pct-ea6b77dd54f1$ /posts/why-im-getting-off-the-pct permanent;
rewrite ^/pct-days-50-56-10b2fa98f098$ /posts/pct-days-50-56 permanent;
rewrite ^/pct-days-44-49-ee05cf1eefea$ /posts/pct-days-44-49 permanent;
rewrite ^/pct-days-40-43-eac6ce1adc89$ /posts/pct-days-40-43 permanent;
rewrite ^/pct-days-35-39-e5d7be41508b$ /posts/pct-days-35-39 permanent;
rewrite ^/pct-days-27-34-dbc24fc02386$ /posts/pct-days-27-34 permanent;
rewrite ^/pct-days-19-26-b9485076eb79$ /posts/pct-days-19-26 permanent;
rewrite ^/pct-days-11-17-f308145ad55$ /posts/pct-days-11-18 permanent;
rewrite ^/pct-days-6-10-8a4baa3b3257$ /posts/pct-days-6-10 permanent;
rewrite ^/pct-days-1-5-23f93dbf707f$ /posts/pct-days-1-5 permanent;
rewrite ^/nourishment-on-the-pct-5c608b0529ba$ /posts/nourishment-on-the-pct permanent;
rewrite ^/i-am-thru-hiking-the-pacific-crest-trail-58a757e5fa79$ /posts/i-am-thru-hiking-the-pacific-crest-trail permanent;
rewrite ^/yosemite-backpacking-trip-2015-7cfbd939956a$ /posts/yosemite-backpacking-trip-2015 permanent;
              '';
              locations = {
                # cache for one hour
                "~* \.(?:atom|json|rss|xml)$" = {
                  extraConfig = ''
expires 1h;
                  '';
                };
                # cache for one year
                "~* \.(?:avif|bmp|bz2|css|doc|gif|gz|htc|ico|jpeg|jpg|js|jxl|map|mjs|mp3|mp4|ogg|ogv|pdf|png|rar|rtf|tar|tgz|wav|weba|webm|webp|woff|woff2|zip)$" = {
                  extraConfig = ''
expires 1y;
                  '';
                };
              };
            };
          };
        };

        deployment.buildOnTarget = true;
        deployment.targetHost = "69.55.55.245";
        deployment.targetUser = "root";
      };
    };
  };
}
