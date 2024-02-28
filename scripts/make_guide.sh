#!/bin/bash

set -o errexit -o nounset -o pipefail

readonly CLI_NAME=${0##*/}
readonly SCRIPT_DIR_RELATIVE=$(dirname "$0")
readonly OUT=$SCRIPT_DIR_RELATIVE/out
FORCE_BUILD=${FORCE_BUILD:-false}

mkdir -p $OUT
debug() { echo $@ >&2; }

guide_type=$1

if [ "$guide_type" == "all" ]; then
    $SCRIPT_DIR_RELATIVE/make_guide.sh "user_guide" "CQL User's Guide" $SCRIPT_DIR_RELATIVE/../docs/user_guide/[0-9]*.md $SCRIPT_DIR_RELATIVE/../docs/user_guide/**/[0-9]*.md
    $SCRIPT_DIR_RELATIVE/make_guide.sh "developer_guide" "CQL Developer's Guide" $SCRIPT_DIR_RELATIVE/../docs/developer_guide/[0-9]*.md
    exit 0
fi

guide_name=$2

debug "Building $guide_type"


# Clean up previous build outputs

mkdir -p "$OUT"
rm -f $OUT/$guide_type.*


# Build Intermediate Markdown output

shift 2
sources=$@
target="$OUT/$guide_type.md"

touch $target
for source in $sources; do
    source_path_from_guide_folder=${source#"$SCRIPT_DIR_RELATIVE/../docs/$guide_type/"}

    if [ "$FORCE_BUILD" != "true" ] && grep -q "<!-- I_AM_A_STUB -->" "$source"; then
        echo "ERROR: $source is a stub, please replace it before building" >&2
        exit 1
    fi

# Replaces front matter section (Yaml header delimitted by ---) with a markdown title header
    awk -v cli_name="$CLI_NAME" -v source_path="$source_path_from_guide_folder" -f - "$source" <<'EOF' >> "$target"
BEGIN {
    FS = "\n";
    front_matter_delimiter_count = 0;

    print "<!--- @generated by " cli_name " -->";
}

function in_front_matter() { return front_matter_delimiter_count == 1 }
function in_markdown() { return front_matter_delimiter_count > 1 }

/^---$/ { front_matter_delimiter_count++; next; }

in_front_matter() && /title:/ {
    title = $0;
    sub(/^.*title: *"*/, "", title);
    sub(/" *$/, "", title);
    print "#", title "\n";
    next;
}

in_markdown() {
    gsub(/\]\(\.[^\.]/, "](./" source_path "/../");
    gsub(/\]\(\.\./, "](./" source_path "/../..");
    print;
}

END { print "<div style=\"page-break-after: always;\"></div>\n" }
EOF

done

debug "$target was successfully created" >&2


# Build Final HTML output

source="$OUT/$guide_type.md"
target="$OUT/$guide_type.html"

pandoc $source \
    --metadata title="$guide_name" \
    --toc \
    --standalone \
    --wrap=none \
    --from markdown \
    --to html \
    --output $target \
    --lua-filter <(cat <<EOF
function Link(element)
    -- If it is not a relative url to a markdown file, do not override the url
    if string.match(element.target, "^%.(.*)%.md") == nil then
        return element
    end

    -- Convert relative urls to markdown files to official website urls
    element.target = "https://ricomariani.github.io/CG-SQL-author/docs/$guide_type/" .. string.gsub(element.target, "%.md", "")

    return element
end
EOF
    )

# change margins to be more reader friendly
sed -e "s/max-width: 36em;/max-width: 70em;/" <$target >$target.tmp
mv $target.tmp $target

debug "$target was successfully created"
