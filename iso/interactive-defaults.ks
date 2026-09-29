# Anaconda interactive defaults for the bootc-fedora-ufficio installer ISO.
# Tells Anaconda which bootc container to install.
#
# Online install (Anaconda pulls the image, needs network):
bootc --source-imgref registry:ghcr.io/laruota/bootc-fedora-ufficio:45 --target-imgref ghcr.io/laruota/bootc-fedora-ufficio:45
#
# Offline install: pass
#   --bootc-installer-payload-ref ghcr.io/laruota/bootc-fedora-ufficio:45
# to `image-builder build`, then use e.g.:
# bootc --source-imgref containers-storage:ghcr.io/laruota/bootc-fedora-ufficio:45 --target-imgref ghcr.io/laruota/bootc-fedora-ufficio:45
