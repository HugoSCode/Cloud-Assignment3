# ===========================================================================
# TO WRITE -- Task 3, Criterion 3.
#
# Worked example: app/catalog/Dockerfile
# See app/orders/Dockerfile for the full set of notes; they apply here too.
# ===========================================================================
#
# WHAT IT MUST PRODUCE
#
#   An image that runs app.py under gunicorn on port 5000, as a non-root
#   user whose UID matches the runAsUser in manifests/05-frontend.yaml.
#
# ONE THING THAT IS DIFFERENT HERE
#
#   This service renders HTML, so it ships a templates/ directory alongside
#   app.py. Check that your build actually includes it -- a `COPY . /app`
#   picks it up, a more selective copy may not, and the failure mode is a
#   TemplateNotFound at the first request rather than at build time.
#
#   While you are there, look at app/frontend/.dockerignore and work out
#   what it is keeping out of the image and why that matters.
#
# HOW TO CHECK
#
#   ./scripts/build-images.sh v1
#   docker run --rm -p 5000:5000 <your-image> &
#   curl -s localhost:5000/ | head -20      # real HTML, not a stack trace
#   docker run --rm <your-image> id         # must NOT be uid=0(root)
