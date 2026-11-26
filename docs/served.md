# nixpkgs packages the cache serves unchanged

Most of what a project needs is in nixpkgs already, built the way it needs
it. Those packages are not rebuilt here. They are listed in the flake's
`served` output instead, at this flake's nixpkgs revision, and uploaded to
the cache with their runtime closures and sources like our own packages.

Why serve them at all, when cache.nixos.org has them:

- A consumer configured with this cache alone, such as a CI job that sets
  it as its only substituter, then needs no second provider, and a path
  the cache lacks shows as a build to refuse rather than a fetch from
  elsewhere.
- The cache keeps them as long as it keeps anything ([sources.md](sources.md));
  cache.nixos.org decides for itself what it keeps.

A consumer gets these paths only when it evaluates them from the same
nixpkgs revision. A flake does that by making its own `nixpkgs` input
follow this flake's:

```nix
inputs.nix-packages.url = "github:701-dev/nix-packages";
inputs.nixpkgs.follows = "nix-packages/nixpkgs";
```

A consumer may compose them further, with wrapper scripts or symbolic
links built from them. Those small derivations are its own and are built
where they are used; what they reference comes from the cache.

## Adding one, or moving the revision

Add the package to `served` in `flake.nix` (by its nixpkgs attribute), then
build and upload it as [uploading.md](uploading.md) says, as
`.#served.<system>.<name>`. Moving the nixpkgs input moves every served
package, and our own, at once: rebuild and upload them all for every
system before a consumer moves its lock to the new revision.

Uploading a served package also uploads its derivation's fixed-output
sources, as for our own (sources.md). For a toolchain that is its whole
bootstrap's tarballs; they are kept like any other source.
