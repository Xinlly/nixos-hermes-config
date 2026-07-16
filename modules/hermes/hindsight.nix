# hindsight.nix — Hindsight memory engine (standalone container)
{ config, pkgs, ... }:
{
  virtualisation.oci-containers.backend = "podman";
  virtualisation.oci-containers.containers.hindsight = {
    image = "ghcr.io/vectorize-io/hindsight:latest";
    # ports 不需要了 — host 网络模式下容器直接共享宿主机端口栈
    volumes = [
      "/var/lib/hermes/.hermes/hindsight/pg0:/home/hindsight/.pg0"
      "/var/lib/hermes/.hermes/hindsight/cache:/home/hindsight/.cache"
    ];
    environmentFiles = [ "/var/lib/hermes/.hermes/hindsight/.env" ];
    extraOptions = [ "--network=host" ];
    environment = {
      HINDSIGHT_API_LLM_PROVIDER = "openai";
      HINDSIGHT_API_LLM_BASE_URL = "https://maas-coding-api.cn-huabei-1.xf-yun.com/v2";
      HINDSIGHT_API_LLM_MODEL = "xopdeepseekv32";
      HINDSIGHT_API_EMBEDDINGS_PROVIDER = "local";
      HINDSIGHT_API_EMBEDDINGS_LOCAL_MODEL = "all-MiniLM-L6-v2";
      HTTP_PROXY = "http://127.0.0.1:35352";
      HTTPS_PROXY = "http://127.0.0.1:35352";
      NO_PROXY = "localhost,127.0.0.1,::1,.xf-yun.com,10.88.0.0/16";
    };
  };
}