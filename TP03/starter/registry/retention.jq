# SemVer 2, avec préfixe v facultatif. Protéger aussi les prereleases.
def semver:
  test("^v?(0|[1-9][0-9]*)\\.(0|[1-9][0-9]*)\\.(0|[1-9][0-9]*)(-((0|[1-9][0-9]*|[0-9]*[A-Za-z-][0-9A-Za-z-]*)(\\.(0|[1-9][0-9]*|[0-9]*[A-Za-z-][0-9A-Za-z-]*))*))?(\\+[0-9A-Za-z-]+(\\.[0-9A-Za-z-]+)*)?$");
map(. + {reason: (
  if (.tag | semver) then "semver"
  elif (.tag | test("^sha256-[a-f0-9]{64}([.].*)?$")) then "artefact de signature/SBOM"
  elif .artifact then "artefact OCI"
  elif .created == null then "date inconnue"
  else null end
)}) as $all
| [$all[] | select(.reason != null)] as $protected
| ([$all[] | select(.reason == null)] | sort_by(.created, .tag) | reverse) as $dated
| ($protected + ($dated[:$keep] | map(.reason = "récent"))) as $kept
| ([$kept[].digests[]] | unique) as $references
| ($dated[$keep:] | map(. + {shared: (.digest as $digest | $references | index($digest) != null)})) as $old
| {
    keep: ($kept | map({tag, digest, created, reason})),
    blocked: [$old[] | select(.shared) | {tag, digest, reason: "manifeste référencé par un tag conservé"}],
    delete: ([$old[] | select(.shared | not)] | group_by(.digest) | map({digest: .[0].digest, tags: map(.tag)}))
  }
