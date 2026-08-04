.PHONY: bump-libpostal

# Point LIBPOSTAL_REF at the current upstream master, so bumping does not mean looking up a
# SHA by hand. Review the diff before committing: libpostal is unversioned between releases
# and a new label in its output makes consumers discard the whole parse. Rebuild and run the
# curl checks after this.
bump-libpostal:
	@sha=$$(curl -fsSL https://api.github.com/repos/openvenues/libpostal/commits/master \
	        | sed -n 's/^  "sha": "\(.*\)",$$/\1/p'); \
	test -n "$$sha" || { echo "could not resolve upstream sha"; exit 1; }; \
	current=$$(sed -n 's/^ARG LIBPOSTAL_REF=//p' Dockerfile); \
	if [ "$$sha" = "$$current" ]; then echo "already at $$sha"; exit 0; fi; \
	sed -i.bak "s/^ARG LIBPOSTAL_REF=.*/ARG LIBPOSTAL_REF=$$sha/" Dockerfile && rm Dockerfile.bak; \
	echo "$$current -> $$sha"; \
	echo "https://github.com/openvenues/libpostal/compare/$$current...$$sha"
