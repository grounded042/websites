{
  description = "websites setup";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-26.05";
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
        exiftool
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

        services.caddy = {
          enable = true;
          email = "grounded042@joncarl.com";

          virtualHosts = {
            # Reject anything that doesn't match jonhikes.com by hostname/SNI
            # (port scanners, IP-direct hits, bad SNI) - closes the connection
            # instead of serving real content, mirroring the old
            # ssl_reject_handshake + return 444 catch-all.
            ":80" = {
              extraConfig = "abort";
            };
            ":443" = {
              extraConfig = "abort";
            };

            "jonhikes.com" = {
              extraConfig = ''
root * /site/jonhikes

# zstd/gzip only - the available brotli modules aren't worth it at the
# compression levels this site would actually use; see caddy-brotli's own
# README recommending zstd+gzip over brotli for that reason.
encode zstd gzip

header Strict-Transport-Security "max-age=63072000; includeSubDomains; preload"

# Known WordPress/PHP scanner noise - close the connection instantly with
# no response instead of paying for a real 404.
@bots path *.php /wp-content/* /wp-admin/* /wp-login* /xmlrpc.php
abort @bots

redir /glacier-2022-day-9-28f136306bca /posts/glacier-2022-day-9 permanent
redir /glacier-2022-day-8-95bc86fadb89 /posts/glacier-2022-day-8 permanent
redir /glacier-2022-day-7-fe9611b18cee /posts/glacier-2022-day-7 permanent
redir /glacier-2022-day-6-8dcb5d01b175 /posts/glacier-2022-day-6 permanent
redir /glacier-2022-day-5-df5c50df0987 /posts/glacier-2022-day-5 permanent
redir /glacier-2022-day-4-937b9d2cd9ce /posts/glacier-2022-day-4 permanent
redir /glacier-2022-day-3-b32c190703b /posts/glacier-2022-day-3 permanent
redir /glacier-2022-day-2-88bc47b2f1cc /posts/glacier-2022-day-2 permanent
redir /glacier-2022-day-1-d502fc01fc43 /posts/glacier-2022-day-1 permanent
redir /glacier-2022-day-0-1dc21adf32f9 /posts/glacier-2022-day-0 permanent
redir /glacier-2022-af4f9139cdc6 /posts/glacier-2022 permanent
redir /why-im-getting-off-the-pct-ea6b77dd54f1 /posts/why-im-getting-off-the-pct permanent
redir /pct-days-50-56-10b2fa98f098 /posts/pct-days-50-56 permanent
redir /pct-days-44-49-ee05cf1eefea /posts/pct-days-44-49 permanent
redir /pct-days-40-43-eac6ce1adc89 /posts/pct-days-40-43 permanent
redir /pct-days-35-39-e5d7be41508b /posts/pct-days-35-39 permanent
redir /pct-days-27-34-dbc24fc02386 /posts/pct-days-27-34 permanent
redir /pct-days-19-26-b9485076eb79 /posts/pct-days-19-26 permanent
redir /pct-days-11-17-f308145ad55 /posts/pct-days-11-18 permanent
redir /pct-days-6-10-8a4baa3b3257 /posts/pct-days-6-10 permanent
redir /pct-days-1-5-23f93dbf707f /posts/pct-days-1-5 permanent
redir /nourishment-on-the-pct-5c608b0529ba /posts/nourishment-on-the-pct permanent
redir /i-am-thru-hiking-the-pacific-crest-trail-58a757e5fa79 /posts/i-am-thru-hiking-the-pacific-crest-trail permanent
redir /yosemite-backpacking-trip-2015-7cfbd939956a /posts/yosemite-backpacking-trip-2015 permanent

@feeds path *.atom *.json *.rss *.xml
@assets path *.avif *.bmp *.bz2 *.css *.doc *.gif *.gz *.htc *.ico *.jpeg *.jpg *.js *.jxl *.map *.mjs *.mp3 *.mp4 *.ogg *.ogv *.pdf *.png *.rar *.rtf *.tar *.tgz *.wav *.weba *.webm *.webp *.woff *.woff2 *.zip

# route preserves literal order; bare `header` directives get auto-sorted
route {
  header Cache-Control "public, max-age=86400"
  header @feeds Cache-Control "public, max-age=3600"
  header @assets Cache-Control "public, max-age=31536000"
}

file_server
              '';
            };
          };
        };

        # Ban repeat WordPress/PHP scanners at the firewall after a few hits,
        # instead of just closing each individual connection via `abort`.
        services.fail2ban = {
          enable = true;
          jails.caddy-scanners = {
            filter = {
              Definition = {
                failregex = ''^.*"client_ip":"<HOST>".*"uri":"(/wp-[a-zA-Z0-9_-]+.*|/xmlrpc\.php.*|[^"]*\.php.*)".*$'';
                ignoreregex = "";
              };
            };
            settings = {
              logpath = "/var/log/caddy/access-jonhikes.com.log";
              backend = "auto";
              findtime = 600;
              maxretry = 3;
              bantime = "1d";
            };
          };
        };

        # Feed goaccess's persistent DB daily so stats survive past Caddy's
        # log rolling (100MiB or 90 days, whichever comes first) instead of
        # only ever reflecting whatever's in the current unrolled log.
        systemd.services.goaccess-report = {
          description = "Update persistent goaccess stats DB and HTML report";
          path = [ pkgs.goaccess ];
          script = ''
            set -euo pipefail

            log=/var/log/caddy/access-jonhikes.com.log
            offset_file=/var/lib/goaccess/offset

            mkdir -p /var/lib/goaccess/db
            last_offset=0
            [ -f "$offset_file" ] && last_offset=$(cat "$offset_file")

            current_size=$(stat -c %s "$log")
            # log got rolled since last run - start over from the new file
            [ "$current_size" -lt "$last_offset" ] && last_offset=0

            tail -c "+$((last_offset + 1))" "$log" | goaccess - \
              --log-format=CADDY \
              --db-path=/var/lib/goaccess/db \
              --persist --restore \
              -o /var/lib/goaccess/report.html

            echo "$current_size" > "$offset_file"
          '';
          serviceConfig.Type = "oneshot";
        };

        systemd.timers.goaccess-report = {
          description = "Daily goaccess stats snapshot";
          wantedBy = [ "timers.target" ];
          timerConfig = {
            OnCalendar = "daily";
            Persistent = true;
          };
        };

        deployment.buildOnTarget = true;
        deployment.targetHost = "69.55.55.245";
        deployment.targetUser = "root";
      };
    };
  };
}
