{
  description = "websites setup";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-23.11";
    nixpkgs-unstable.url = "github:nixos/nixpkgs/nixpkgs-unstable";
  };

  outputs = { self, nixpkgs, ...}@inputs: let
    pkgs = import nixpkgs {
      system = "x86_64-linux";
    };
  in {
    colmena = {
      meta = {
        nixpkgs = pkgs;
      };

      defaults = { pkgs, ... }: {
        environment.systemPackages = with pkgs; [
          static-web-server
        ];
      };

      webserver = { modulesPath, lib, ... }: {
        imports = lib.optional (builtins.pathExists ./do-userdata.nix) ./do-userdata.nix ++ [
          (modulesPath + "/virtualisation/digital-ocean-config.nix")
        ];

        system.stateVersion = "23.11";

        networking.firewall.allowedTCPPorts = [ 22 80 443 ];

        services.nginx = {
          enable = false;
          virtualHosts.default = {
            default = true;
            root = "/site/jonhikes";
          };
        };

        security.acme = {
          acceptTerms = true;
          defaults.email = "me@joncarl.com";
          certs."jonhikes.com" = {
            reloadServices = [ "static-web-server" ];
            listenHTTP = ":80";
            keyType = "ec384";
          };
        };

        users.users.static-web-server = {
          isSystemUser = true;
          group = "acme";
        };

        services.static-web-server = {
          enable = true;
          listen = "[::]:443";
          root = "/site/jonhikes";
          configuration = {
            general = {
              http2 = true;
              http2-tls-cert = "/var/lib/acme/jonhikes.com/fullchain.pem";
              http2-tls-key = "/var/lib/acme/jonhikes.com/key.pem";
            };
            advanced = {
              redirects = [
                {
                  source = "/glacier-2022-day-9-28f136306bca";
                  destination = "/posts/glacier-2022-day-9";
                  kind = 301;
                }
                {
                  source = "/glacier-2022-day-8-95bc86fadb89";
                  destination = "/posts/glacier-2022-day-8";
                  kind = 301;
                }
                {
                  source = "/glacier-2022-day-7-fe9611b18cee";
                  destination = "/posts/glacier-2022-day-7";
                  kind = 301;
                }
                {
                  source = "/glacier-2022-day-6-8dcb5d01b175";
                  destination = "/posts/glacier-2022-day-6";
                  kind = 301;
                }
                {
                  source = "/glacier-2022-day-5-df5c50df0987";
                  destination = "/posts/glacier-2022-day-5";
                  kind = 301;
                }
                {
                  source = "/glacier-2022-day-4-937b9d2cd9ce";
                  destination = "/posts/glacier-2022-day-4";
                  kind = 301;
                }
                {
                  source = "/glacier-2022-day-3-b32c190703b";
                  destination = "/posts/glacier-2022-day-3";
                  kind = 301;
                }
                {
                  source = "/glacier-2022-day-2-88bc47b2f1cc";
                  destination = "/posts/glacier-2022-day-2";
                  kind = 301;
                }
                {
                  source = "/glacier-2022-day-1-d502fc01fc43";
                  destination = "/posts/glacier-2022-day-1";
                  kind = 301;
                }
                {
                  source = "/glacier-2022-day-0-1dc21adf32f9";
                  destination = "/posts/glacier-2022-day-0";
                  kind = 301;
                }
                {
                  source = "/glacier-2022-af4f9139cdc6";
                  destination = "/posts/glacier-2022";
                  kind = 301;
                }
                {
                  source = "/why-im-getting-off-the-pct-ea6b77dd54f1";
                  destination = "/posts/why-im-getting-off-the-pct";
                  kind = 301;
                }
                {
                  source = "/pct-days-50-56-10b2fa98f098";
                  destination = "/posts/pct-days-50-56";
                  kind = 301;
                }
                {
                  source = "/pct-days-44-49-ee05cf1eefea";
                  destination = "/posts/pct-days-44-49";
                  kind = 301;
                }
                {
                  source = "/pct-days-40-43-eac6ce1adc89";
                  destination = "/posts/pct-days-40-43";
                  kind = 301;
                }
                {
                  source = "/pct-days-35-39-e5d7be41508b";
                  destination = "/posts/pct-days-35-39";
                  kind = 301;
                }
                {
                  source = "/pct-days-27-34-dbc24fc02386";
                  destination = "/posts/pct-days-27-34";
                  kind = 301;
                }
                {
                  source = "/pct-days-19-26-b9485076eb79";
                  destination = "/posts/pct-days-19-26";
                  kind = 301;
                }
                {
                  source = "/pct-days-11-17-f308145ad55";
                  destination = "/posts/pct-days-11-18";
                  kind = 301;
                }
                {
                  source = "/pct-days-6-10-8a4baa3b3257";
                  destination = "/posts/pct-days-6-10";
                  kind = 301;
                }
                {
                  source = "/pct-days-1-5-23f93dbf707f";
                  destination = "/posts/pct-days-1-5";
                  kind = 301;
                }
                {
                  source = "/nourishment-on-the-pct-5c608b0529ba";
                  destination = "/posts/nourishment-on-the-pct";
                  kind = 301;
                }
                {
                  source = "/i-am-thru-hiking-the-pacific-crest-trail-58a757e5fa79";
                  destination = "/posts/i-am-thru-hiking-the-pacific-crest-trail";
                  kind = 301;
                }
                {
                  source = "/yosemite-backpacking-trip-2015-7cfbd939956a";
                  destination = "/posts/yosemite-backpacking-trip-2015";
                  kind = 301;
                }
              ];
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
