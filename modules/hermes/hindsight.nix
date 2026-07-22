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
      "/var/lib/hermes/.hermes/hindsight/patches/memory_engine.py:/app/api/hindsight_api/engine/memory_engine.py:ro"
    ];
    environmentFiles = [ "/var/lib/hermes/.hermes/hindsight/.env" ];
    extraOptions = [ "--network=host" ];
    environment = {
      HINDSIGHT_API_LLM_PROVIDER = "deepseek";
      HINDSIGHT_API_LLM_BASE_URL = "https://api.deepseek.com";
      HINDSIGHT_API_LLM_MODEL = "deepseek-v4-flash";
      HINDSIGHT_API_EMBEDDINGS_PROVIDER = "local";
      HINDSIGHT_API_EMBEDDINGS_LOCAL_MODEL = "all-MiniLM-L6-v2";
      HTTP_PROXY = "http://127.0.0.1:35352";
      HTTPS_PROXY = "http://127.0.0.1:35352";
      NO_PROXY = "localhost,127.0.0.1,::1,.xf-yun.com,10.88.0.0/16";
    };
  };
}