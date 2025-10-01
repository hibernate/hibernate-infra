let HibernateDoc;
if (!HibernateDoc) {
    HibernateDoc = {};
}

HibernateDoc.OutdatedContent = (function () {
    const install = function (project, basepath) {
        // sanitize project value
        if (!/[a-z]+/.exec(project)) {
            return;
        }
        if (!basepath) {
            basepath = '/hibernate/_outdated-content/';
        }

        // build the url to redirect to
        jQuery_3_1.getJSON(basepath + project + '.json', function (json) {
            const button = document.getElementById('versionSelectButton');
            const dropdown = document.getElementById('versionSelectList');

            if (button && dropdown) { // Function to render the version list
                const renderVersions = (list) => {
                    // first figure out the url pattern:
                    // e.g. /hibernate/stable/search/reference/en-US/html_single/
                    const versionPattern = /(\/[\d.]+\/|\/current|\/stable\/)/;

                    const currentPath = window.location.pathname;
                    const currentVersionMatch = currentPath.match(versionPattern);

                    if (!currentVersionMatch) {
                        console.warn("Could not find a version ('X.Y', 'current', or 'stable') in the current path. Skipping version dropdown construction.");
                        button.className = 'hidden';
                        return;
                    }

                    const versionSegment = currentVersionMatch[0];

                    dropdown.innerHTML = '';
                    list.forEach(version => {
                        const item = document.createElement('a');
                        item.textContent = version;
                        item.className = 'version-dropdown-item';
                        item.href = currentPath.replace(versionSegment, `/${version}/`);
                        dropdown.appendChild(item);
                    });
                };

                // Extract version tags from the response
                const versions = json.versions.map(v => v.version);
                renderVersions(versions);

                // Event listener for button click
                button.addEventListener('click', (e) => {
                    if (dropdown.style.display === 'block') {
                        dropdown.style.display = 'none';
                    } else {
                        dropdown.style.display = 'block';
                    }
                    e.stopPropagation();
                });

                // Hide dropdown when clicking outside
                document.addEventListener('click', (e) => {
                    if (!e.target.closest('#versionSelect')) {
                        dropdown.style.display = 'none';
                    }
                });
            }

            // Follow the scroll of the user to choose the best hash possible
            let currentHash = window.location.hash;
            jQuery_3_1(document).scroll(function () {
                // in order: html docbook output, html5 docbook output, asciidoc output
                jQuery_3_1('h2 > a[id], h3 > a[id], section[id], h2[id], h3[id]').each(function () {
                    const hash = jQuery_3_1(this).attr('id');
                    if (/^d0e[0-9]+$/.exec(hash)) {
                        // we don't consider the numeric hashes as they have been renamed to strings later
                        return;
                    }
                    const top = window.scrollY;
                    const distance = top - jQuery_3_1(this).offset().top;
                    if (distance < 30 && distance > -30 && currentHash !== hash) {
                        if (history.replaceState) {
                            history.replaceState(null, null, "#" + hash);
                        } else {
                            window.location.hash = '#' + hash;
                        }
                        currentHash = hash;
                    }
                });
            });

            const currentUrl = window.location.pathname;
            let stableUrl;
            let pageHash;

            // multi page
            const matchMulti = new RegExp(json.multi.pattern).exec(currentUrl);
            const matchSingle = new RegExp(json.single.pattern).exec(currentUrl);

            if (matchMulti && matchMulti.length === 3) {
                const currentVersion = matchMulti[1];
                const currentPage = matchMulti[2];

                if (currentVersion === json.stable || _isNewerThan(currentVersion, json.stable) || currentVersion === 'stable' || currentVersion === 'current') {
                    return;
                }

                const redirectToMultiPage = (json.multi.target.indexOf('${page}') > -1);

                if (redirectToMultiPage) {
                    let i = 0;
                    let redirectStart = 0;
                    let redirectEnd = 0;
                    for (let versionInformation of json.versions) {
                        if (versionInformation.version === json.stable) {
                            redirectEnd = i;
                        }
                        if (versionInformation.version === currentVersion) {
                            redirectStart = i;
                            break;
                        }
                        i++;
                    }

                    if (redirectStart === 0) {
                        return;
                    }

                    let redirectPage = currentPage;
                    for (let j = redirectStart; j >= redirectEnd; j--) {
                        if (!('redirects' in json.versions[j])) {
                            continue;
                        }
                        if (redirectPage in json.versions[j].redirects) {
                            redirectPage = json.versions[j].redirects[redirectPage];
                        }
                    }

                    stableUrl = json.multi.target.replace('${version}', json.stable).replace('${page}', redirectPage);
                } else {
                    pageHash = jQuery_3_1('div.titlepage h2.title a').attr('id');
                    stableUrl = json.multi.target.replace('${version}', json.stable);
                }
            } else if (matchSingle && matchSingle.length > 2) {
                const currentVersion = matchSingle[1];
                if (currentVersion === json.stable || _isNewerThan(currentVersion, json.stable) || currentVersion === 'stable' || currentVersion === 'current') {
                    return;
                }

                if (json.single.useCurrentUrl) {
                    stableUrl = currentUrl.replace(currentVersion, json.stable);
                } else {
                    stableUrl = json.single.target.replace('${version}', json.stable).replace('${page}', '');
                }
            } else {
                return;
            }

            stableUrl += '?v=' + json.stable;

            jQuery_3_1('head').append('<style type="text/css">' +
                'body {' +
                '	padding-bottom: 50px;' +
                '}' +
                '.outdated-content {' +
                '	position: fixed;' +
                '	bottom: 0;' +
                '	left: 0;' +
                '	text-align:center;' +
                '	width:100%;' +
                '	padding: 20px;' +
                '	background-color: #ffbc3b;' +
                '	border-top: 1px solid #ffbc3b;' +
                '	font-weight: bold;' +
                '	font-size: 20px;' +
                '	color: white;' +
                '	text-shadow: 0 1px 1px rgba(85, 85, 85, 0.55);' +
                '	z-index: 1001;' +
                '}' +
                'a.version {' +
                '	border: 1px solid #AAA;' +
                '	border-radius: 4px;' +
                '	background-color: #BBB;' +
                '	padding: 3px 8px;' +
                '	color: white;' +
                '	text-shadow: 0 1px 1px rgba(85, 85, 85, 0.55);	' +
                '	text-decoration: none;' +
                '}' +
                'a.version:hover {' +
                '	background-color: #CCC;' +
                '}' +
                'a#close-outdated {' +
                '	float:right; ' +
                '	margin-right: 40px;' +
                '	cursor: pointer;' +
                '	text-decoration:none;' +
                '	color: white;' +
                '	font-weight: bold;' +
                '}' +
                '#toc.toc2 > ul {' +
                '	margin-bottom: 8em;' +
                '}' +
                '</style>');
            if (document.cookie.indexOf('hibernate-doc-hide-outdated-cookie=true') === -1) {
                jQuery_3_1('body').append('<div class="outdated-content">This content refers to an earlier version of ' + json.project + '. Go to latest stable: <a id="stable-url" href="' + stableUrl + '" class="version">version ' + json.stable + '</a>.<a id="close-outdated" title="Close this banner">&times;</a></div>');
                jQuery_3_1('a#stable-url').on('click', function (e) {
                    e.preventDefault();
                    let url = this.href;
                    if (window.location.hash !== '' && window.location.hash !== '#' && !/^#d0e[0-9]+$/.exec(window.location.hash)) {
                        url += window.location.hash;
                    } else if (pageHash) {
                        url += '#' + pageHash;
                    }
                    window.location.href = url;
                });
                jQuery_3_1('a#close-outdated').on('click', function (e) {
                    e.preventDefault();
                    jQuery_3_1('.outdated-content').hide();
                    document.cookie = 'hibernate-doc-hide-outdated-cookie=true; path=/';
                });
            }
        });
    }

    const _isNewerThan = function (version, reference) {
        const versionObject = _extractVersion(version);
        const referenceObject = _extractVersion(reference);
        if (versionObject.major === referenceObject.major) {
            return versionObject.minor > referenceObject.minor;
        }
        return versionObject.major > referenceObject.major;
    }

    const _extractVersion = function (version) {
        const match = /([0-9]+)\.([0-9]+)/.exec(version);
        if (match.length !== 3) {
            return null;
        }
        return {major: parseInt(match[1]), minor: parseInt(match[2])};
    }

    return {
        install: install
    }
})();