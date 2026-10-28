# ===========================================================================
# TO WRITE -- Task 3, Criterion 3.
#
# Worked example: app/catalog/Dockerfile
#
# This file is empty of instructions, so `docker build` will fail until you
# write it. Replace these comments entirely; do not leave them in a file you
# submit.
# ===========================================================================
#
# WHAT IT MUST PRODUCE
#
#   An image that runs app.py under gunicorn on port 5000, as a non-root
#   user whose UID matches the runAsUser in manifests/04-orders.yaml, with
#   the dependencies in requirements.txt installed.
#
#   scripts/build-images.sh builds and tags it. Read that script to see the
#   image name and registry it expects, and the build context it passes.
#
# YOU MAY COPY THE CATALOG DOCKERFILE
#
#   It will very likely be identical. The services differ in what they
#   import, which is expressed in requirements.txt, not in the build.
#   Copying it is not cheating; pretending you wrote something different is.
#   Say in your report that the three builds are the same and why that is
#   the correct outcome rather than a missed opportunity.
#
#   Then answer the question that actually carries the marks: should these
#   three services share one Dockerfile instead of holding three copies of
#   the same file? There is a real trade-off. Take a position.
#
# THINGS YOU WILL BE ASKED IN THE CODE DEFENSE
#
#   1. Why does requirements.txt get copied and installed before the rest
#      of the source, rather than copying everything at once? Answer in
#      terms of what Docker caches and what invalidates the cache.
#
#   2. Why python:3.11-slim rather than python:3.11, or alpine, or a
#      distroless base? Name what each one costs you.
#
#   3. The image runs as UID 10001. What does that actually prevent, given
#      that the container is already isolated? What does it not prevent?
#
#   4. Why one gunicorn worker and not four? This one is specific to this
#      application -- the answer is in how prometheus_client stores its
#      counters, and getting it wrong produces metrics that are wrong in a
#      way nothing warns you about. If you raise the worker count, you must
#      also explain what else you would have to change.
#
#   5. What is in this image that does not need to be, and how would you
#      find out? (`docker history`, and a look at the image size, are the
#      start of a Distinction-level answer.)
#
# HOW TO CHECK
#
#   ./scripts/build-images.sh v1
#   curl -s http://localhost:32000/v2/_catalog
#   docker run --rm -p 5000:5000 <your-image> &
#   curl -s localhost:5000/healthz
#   curl -s localhost:5000/metrics | head
#   docker run --rm <your-image> id        # must NOT be uid=0(root)
