#!/bin/bash -e

# The content of this generated file can be copy-pasted to
# relevant places in roles/websites/files/etc/httpd/conf.d/docs.hibernate.org-rewriterules.confpart
rm -f rewriterules.tmp

rewriterule() {
  rewritecond="$1"
  rewriterule_match="$2"
  rewriterule_replace="$3"
  perl -wpe "s,$rewriterule_match,$rewriterule_replace,g if m,$rewritecond,"
  {
    echo "RewriteCond %{REQUEST_URI} $rewritecond"
    echo "RewriteRule $rewriterule_match $rewriterule_replace $4"
  } >> rewriterules.tmp
}

toindex_part() {
  rewriterule \
    '^/(?:orm/[^/]+|stable/orm)/' \
    "^(.*)/($1)$2$" \
    '$1/$2' \
    '[R=301,L,E=nocache:1]'
}

toindex() {
  toindex_part "dialect/" "dialect.html" \
    | toindex_part "integrationguide/html_single/" "Hibernate_Integration_Guide.html" \
    | toindex_part "introduction/html_single/" "Hibernate_Introduction.html" \
    | toindex_part "migration-guide/" "migration-guide.html" \
    | toindex_part "querylanguage/html_single/" "Hibernate_Query_Language.html" \
    | toindex_part "repositories/html_single/" "Hibernate_Data_Repositories.html" \
    | toindex_part "userguide/html_single/" "Hibernate_User_Guide.html" \
    | toindex_part "whats-new/" "whats-new.html"
}

fromindex_part() {
  rewriterule \
    '^/(?:orm/[3456]\.[^/]+|orm/7\.[01]|stable/orm|orm/current)/' \
    "^(.*)/($1)(index\.html)?$" \
    "\$1/\$2$2" \
    '[L]'
}

fromindex() {
  fromindex_part "dialect/" "dialect.html" \
    | fromindex_part "integrationguide/html_single/" "Hibernate_Integration_Guide.html" \
    | fromindex_part "introduction/html_single/" "Hibernate_Introduction.html" \
    | fromindex_part "migration-guide/" "migration-guide.html" \
    | fromindex_part "querylanguage/html_single/" "Hibernate_Query_Language.html" \
    | fromindex_part "repositories/html_single/" "Hibernate_Data_Repositories.html" \
    | fromindex_part "userguide/html_single/" "Hibernate_User_Guide.html" \
    | fromindex_part "whats-new/" "whats-new.html"
}

toindex <paths >1.tmp

echo "===================================================================="
echo "REDIRECTION 1 PROBLEMS (should be empty)"
echo "===================================================================="
# Most *.html files should be renamed to "/" (no HTML file name, implicit index.html)
# We ignore files that *should not* be redirected
grep -E '/(orm/[^/]+|stable/orm)/' 1.tmp | grep -Ev '/$|index.html$' \
  | grep -Ev '/html/|/html_single/chapters/|/html_single/appendices/' \
  | grep -Ev 'legalnotice.html|Legal_Notice.html|Preface.html|ln-d5e19.html|Bibliography.html' \
  | grep -Ev 'topical/html_single/[^/]+/[^/]+.html' \
  | grep -Ev 'logging/logging.html' \
  | grep -Ev 'quickstart/html_single' \
  || true
echo "===================================================================="
echo "END"
echo "===================================================================="

echo >> rewriterules.tmp
fromindex <1.tmp >2.tmp

echo "===================================================================="
echo "REDIRECTION 2 PROBLEMS (should be empty)"
echo "===================================================================="
# Applying redirection 1 then 2 should result in the initial paths
diff -C 0 --color paths 2.tmp || true
echo "===================================================================="
echo "END"
echo "===================================================================="
