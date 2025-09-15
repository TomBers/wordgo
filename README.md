# wordgo

## Bundling Bumblebee model cache into the Docker image (offline, no SSH needed)

If you already have the Hugging Face model on your local machine and want to avoid logging into the running machine to populate the cache, you can ship the cache inside the image and run Bumblebee fully offline.

Important: If you mount a Fly volume at the same path as your cache inside the image, the mount will hide the baked-in files. Choose one of the two approaches below.

### Option A — Image-only (no volume)

- On your local machine, locate Bumblebee’s cache directory for the model, typically:
  - macOS/Linux: ~/.cache/bumblebee/huggingface/BAAI--bge-small-en-v1.5
- Copy that directory into the repo under priv so it’s tracked and available at build time:
  - priv/bumblebee-cache/huggingface/BAAI--bge-small-en-v1.5
- In the Dockerfile final stage, copy the cache into the image and set environment variables to use it offline. Example:
    ENV BUMBLEBEE_CACHE_DIR=/app/priv/bumblebee-cache
    ENV BUMBLEBEE_OFFLINE=true
    COPY --chown=nobody:root priv/bumblebee-cache /app/priv/bumblebee-cache
- Make sure your runtime config reads the env var (already supported in runtime.exs):
    config :bumblebee, :cache_dir, System.get_env("BUMBLEBEE_CACHE_DIR") || "/data/bumblebee-cache"
- Deploy as usual. The model will load from the baked-in cache with no network access required.

### Option B — Volume-backed persistence (with pre-seeded cache)

If you want the cache in a Fly volume (so it can be updated at runtime and persist independently of images) but still want to pre-seed it without SSH:

- Do NOT mount the volume at the same path you copy into the image, or the mount will hide your baked-in files.
- Pick two paths:
  - Bake-in path in the image (read-only source): /app/priv/bumblebee-cache
  - Mounted volume (read-write target): /data/bumblebee-cache
- In the Dockerfile final stage:
    COPY --chown=nobody:root priv/bumblebee-cache /app/priv/bumblebee-cache
- Keep your Fly mount at /data and set BUMBLEBEE_CACHE_DIR to /data/bumblebee-cache in fly.toml.
- Add a tiny bootstrapping step (entrypoint or start script) that, on first boot only, copies from the baked-in path to the empty volume:
    if [ ! -d "/data/bumblebee-cache/huggingface" ]; then
      cp -R /app/priv/bumblebee-cache/* /data/bumblebee-cache/
      chown -R 65534:65534 /data/bumblebee-cache
    fi
- After the initial copy, set:
    BUMBLEBEE_CACHE_DIR=/data/bumblebee-cache
    BUMBLEBEE_OFFLINE=true
- This gives you an updatable, persistent cache while still being fully offline at model load.

### Notes

- Keep BUMBLEBEE_OFFLINE=true in production if you require strictly offline operation.
- If you switch between image-only and volume-backed approaches, ensure BUMBLEBEE_CACHE_DIR points to the correct location and avoid path collisions that cause mounts to hide baked-in files.
- If you ever change model versions, re-seed the cache (rebuild the image for Option A, or re-copy into the volume for Option B).

To start your Phoenix server:

* Run `mix setup` to install and setup dependencies
* Start Phoenix endpoint with `mix phx.server` or inside IEx with `iex -S mix phx.server`

Now you can visit [`localhost:4000`](http://localhost:4000) from your browser.

Ready to run in production? Please [check our deployment guides](https://hexdocs.pm/phoenix/deployment.html).

## Learn more

* Official website: https://www.phoenixframework.org/
* Guides: https://hexdocs.pm/phoenix/overview.html
* Docs: https://hexdocs.pm/phoenix
* Forum: https://elixirforum.com/c/phoenix-forum
* Source: https://github.com/phoenixframework/phoenix
