#!/usr/bin/python3
import os
import sys
import re
import logging
from typing import Any, Optional
import datetime
import requests
from copy import deepcopy

__apps = {
    'module_vts': {
        'type': 'github_tag',
        'github': 'vozlt/nginx-module-vts',
        'match': r'^(?!.*[rR][cC][0-9]*$)v?[0-9.]+[-]?.*$',
    },
    'module_more': {
        'type': 'github_tag',
        'github': 'openresty/headers-more-nginx-module',
        'match': r'^(?!.*[rR][cC][0-9]*$)v?[0-9.]+[-]?.*$',
    },
    'module_ndk': {
        'type': 'github_tag',
        'github': 'vision5/ngx_devel_kit',
        'match': r'^(?!.*[rR][cC][0-9]*$)v?[0-9.]+[-]?.*$',
    },
    'module_lua': {
        'type': 'github_tag',
        'github': 'openresty/lua-nginx-module',
        'match': r'^(?!.*[rR][cC][0-9]*$)v?[0-9.]+[-]?.*$',
    },
    'module_lua_stream': {
        'type': 'github_tag',
        'github': 'openresty/stream-lua-nginx-module',
        'match': r'^(?!.*[rR][cC][0-9]*$)v?[0-9.]+[-]?.*$',
    },
    'module_lua_upstream': {
        'type': 'github_tag',
        'github': 'openresty/lua-upstream-nginx-module',
        'match': r'^(?!.*[rR][cC][0-9]*$)v?[0-9.]+[-]?.*$',
    },
    'module_ratelimit': {
        'type': 'github_tag',
        'github': 'weserv/rate-limit-nginx-module',
        'match': r'^(?!.*[rR][cC][0-9]*$)v?[0-9.]+[-]?.*$',
    },
    'module_replace_filter': {
        'type': 'github_tag',
        'github': 'openresty/replace-filter-nginx-module',
    },
    'module_echo': {
        'type': 'github_tag',
        'github': 'openresty/echo-nginx-module',
        'match': r'^(?!.*[rR][cC][0-9]*$)v?[0-9.]+[-]?.*$',
    },
    'lua_jit': {
        'type': 'github_tag',
        'github': 'openresty/luajit2',
        'match': r'^(?!.*[bB][eE][tT][aA][0-9]*$)v?[0-9.]+[-]?.*$',
    },
    'lua_core': {
        'type': 'github_tag',
        'github': 'openresty/lua-resty-core',
        'match': r'^(?!.*[rR][cC][0-9]*$)v?[0-9.]+[-]?.*$',
    },
    'lua_lrucache': {
        'type': 'github_tag',
        'github': 'openresty/lua-resty-lrucache',
        'match': r'^(?!.*[rR][cC][0-9]*$)v?[0-9.]+[-]?.*$',
    },
    'lua_hmac': {
        'type': 'github_tag',
        'github': 'jkeys089/lua-resty-hmac',
        'match': r'^(?!.*[rR][cC][0-9]*$)v?[0-9.]+[-]?.*$',
    },
    'lua_string': {
        'type': 'github_tag',
        'github': 'openresty/lua-resty-string',
        'match': r'^(?!.*[rR][cC][0-9]*$)v?[0-9.]+[-]?.*$',
    },
    'lua_websocket': {
        'type': 'github_tag',
        'github': 'openresty/lua-resty-websocket',
        'match': r'^(?!.*[rR][cC][0-9]*$)v?[0-9.]+[-]?.*$',
    },
    'lua_shdict': {
        'type': 'github_tag',
        'github': 'openresty/lua-resty-shdict-simple',
    },
    'lua_hc': {
        'type': 'github_tag',
        'github': 'openresty/lua-resty-upstream-healthcheck',
        'match': r'^(?!.*[rR][cC][0-9]*$)v?[0-9.]+[-]?.*$',
    },
    'lua_memcached': {
        'type': 'github_tag',
        'github': 'openresty/lua-resty-memcached',
        'match': r'^(?!.*[rR][cC][0-9]*$)v?[0-9.]+[-]?.*$',
    },
    'lua_dns': {
        'type': 'github_tag',
        'github': 'openresty/lua-resty-dns',
        'match': r'^(?!.*[rR][cC][0-9]*$)v?[0-9.]+[-]?.*$',
    },
    'lua_lock': {
        'type': 'github_tag',
        'github': 'openresty/lua-resty-lock',
        'match': r'^(?!.*[rR][cC][0-9]*$)v?[0-9.]+[-]?.*$',
    },
    'lua_shell': {
        'type': 'github_tag',
        'github': 'openresty/lua-resty-shell',
        'match': r'^(?!.*[rR][cC][0-9]*$)v?[0-9.]+[-]?.*$',
    },
    'lua_redis': {
        'type': 'github_tag',
        'github': 'openresty/lua-resty-redis',
        'match': r'^(?!.*[rR][cC][0-9]*$)v?[0-9.]+[-]?.*$',
    },
    'lua_cjson': {
        'type': 'github_tag',
        'github': 'openresty/lua-cjson',
        'match': r'^(?!.*[rR][cC][0-9]*$)v?[0-9.]+[-]?.*$',
    },
    'lua_sregex': {
        'type': 'github_tag',
        'github': 'openresty/sregex',
        'match': r'^(?!.*[rR][cC][0-9]*$)v?[0-9.]+[-]?.*$',
    },
    'lua_jwt': {
        'type': 'github_tag',
        'github': 'SkyLothar/lua-resty-jwt',
        'match': r'^(?!.*[rR][cC][0-9]*$)v?[0-9.]+[-]?.*$',
    },
    'lua_ipmatcher': {
        'type': 'github_tag',
        'github': 'api7/lua-resty-ipmatcher',
        'match': r'^(?!.*[rR][cC][0-9]*$)v?[0-9.]+[-]?.*$',
    },
    'gotemplate': {
        'type': 'github_release',
        'github': 'coveooss/gotemplate',
    },
    'alpine': {
        'type': 'alpine',
        'rules': [
            {   # not everyone has adopted it yet
                'match': r'^3[.]24$',
                'action': 'drop',
                'until': '2026-10-01',
            },
            {
                'match': r'^3[.][0-9]+$',
                'action': 'keep',
            },
        ]
    },
    'nginx': {
        'type': 'github_tag',
        'github': 'nginx/nginx',
        'match': r'^(?!.*[rR][cC][0-9]*$)release-[0-9.]+[-]?.*$',
        'match_extract': r'^release-([0-9.]+[-]?.*)$',
    },
}


__dockerfile = os.path.join(os.path.curdir, 'Dockerfile')


def __filter_by_match(versions: list[str], match: str) -> list[str]:
    pattern = re.compile(match)
    return [v for v in versions if pattern.match(v)]


def __filter_by_match_extract(versions: list[str], match_extract: str) -> list[str]:
    pattern = re.compile(match_extract)

    regroup = []
    for v in versions:
        match = pattern.match(v)
        if match:
            regroup.append(match.group(1))
    return regroup


def __filter_strip(versions: list[str]) -> list[str]:
    return [v.strip(' v') for v in versions]


def __filter_by_rules(versions: list[str], rules: list[dict]) -> list[str]:
    today = datetime.date.today().isoformat()

    def rule_active(rule: dict) -> bool:
        since = rule.get('since')
        until = rule.get('until')
        if since and today < since:
            return False
        if until and today >= until:
            return False
        return True

    keep_patterns = [re.compile(r['match']) for r in rules if r['action'] == 'keep' and rule_active(r)]  # type: ignore
    drop_patterns = [re.compile(r['match']) for r in rules if r['action'] == 'drop' and rule_active(r)]  # type: ignore

    def allowed(version: str) -> bool:
        if any(p.match(version) for p in drop_patterns):
            return False
        if any(p.match(version) for p in keep_patterns):
            return True
        return False  # no keep rule matched: drop by default

    versions = [v for v in versions if allowed(v)]

    return versions


def version_github_release(github: str, **kvargs: dict[str, Any]) -> Optional[str]:
    count = 100
    headers = {
        'X-GitHub-Api-Version': '2026-03-10',
    }
    if os.environ.get('GITHUB_TOKEN', '') != '':
        headers['Authorization'] = 'Bearer ' + os.environ.get('GITHUB_TOKEN', '')

    response = requests.get(
        url=f'https://api.github.com/repos/{github}/releases?per_page={count}',
        headers=headers,
    )
    response.raise_for_status()
    releases = response.json()

    releases.sort(key=lambda r: r['published_at'], reverse=True)
    tags = [tag['tag_name'] for tag in releases]

    if 'match' in kvargs:
        tags = __filter_by_match(tags, kvargs['match'])  # type: ignore

    if len(tags) == 0:
        return None

    if 'match_extract' in kvargs:
        tags = __filter_by_match_extract(tags, kvargs['match_extract'])  # type: ignore
    else:
        tags = __filter_strip(tags)  # type: ignore

    if len(tags) == 0:
        return None

    def key(v):
        nums = re.findall(r'\d+', v)
        return tuple(map(int, nums))

    return max(tags, key=key)


def version_github_tag(github: str, **kvargs: dict[str, Any]) -> Optional[str]:
    count = 100
    headers = {
        'X-GitHub-Api-Version': '2026-03-10',
    }
    if os.environ.get('GITHUB_TOKEN', '') != '':
        headers['Authorization'] = 'Bearer ' + os.environ.get('GITHUB_TOKEN', '')

    response = requests.get(
        url=f'https://api.github.com/repos/{github}/tags?per_page={count}',
        headers=headers,
    )
    response.raise_for_status()
    tags = response.json()

    tags = [tag['name'] for tag in tags]

    if 'match' in kvargs:
        tags = __filter_by_match(tags, kvargs['match'])  # type: ignore

    if len(tags) == 0:
        return None

    if 'match_extract' in kvargs:
        tags = __filter_by_match_extract(tags, kvargs['match_extract'])  # type: ignore
    else:
        tags = __filter_strip(tags)  # type: ignore

    if len(tags) == 0:
        return None

    def key(v):
        nums = re.findall(r'\d+', v)
        return tuple(map(int, nums))

    return max(tags, key=key)


def version_alpine(**kvargs: dict[str, Any]) -> Optional[str]:
    response = requests.get(
        url=f'https://dl-cdn.alpinelinux.org/alpine/',
        allow_redirects=True,
    )
    response.raise_for_status()
    html = response.text

    links = re.findall(r'<a href="([^"]+)">([^<]+)</a>', html)
    links = [(href, text) for href, text in links if href == text]

    pattern = re.compile(r'^v?[0-9._-]+[a-zA-Z0-9._-]*$')

    versions = []
    for href, _ in links:
        name = href.strip(' /')
        if pattern.match(name):
            versions.append(name)

    if 'match' in kvargs:
        versions = __filter_by_match(versions, kvargs['match'])  # type: ignore

    if len(versions) == 0:
        return None

    if 'match_extract' in kvargs:
        versions = __filter_by_match_extract(versions, kvargs['match_extract'])  # type: ignore
    else:
        versions = __filter_strip(versions)  # type: ignore

    rules: list = kvargs.get('rules', [])  # type: ignore
    if rules:
        versions = __filter_by_rules(versions, rules)

    if len(versions) == 0:
        return None

    def key(v):
        nums = re.findall(r'\d+', v)
        return tuple(map(int, nums))

    return max(versions, key=key)


def main() -> None:
    logging.basicConfig(
        level=logging.INFO,
        format='%(asctime)s,%(msecs)03d [%(levelname)s]: %(message)s',
        datefmt='%Y-%m-%d %H:%M:%S',
    )

    debug = False
    if '--debug' in sys.argv or '-d' in sys.argv:
        debug = True

    upgrades = []
    lines = []

    search = re.compile(r'^ARG[ ]+(?P<name>[^=]+)=(?P<value>[^#]+)(?P<comment>|#.+)$')
    with open(__dockerfile, 'r') as fd:
        for line in fd.readlines():
            lines.append(line.rstrip(' \n'))

            groups = search.match(line)
            if groups is not None:
                name = groups.group('name').strip(' \n')
                value = groups.group('value').strip(' \n')
                comment = groups.group('comment').strip(' \n')

                if not name.endswith('_VERSION'):
                    continue

                appname = name.replace('_VERSION', '').lower()

                if appname not in __apps.keys():
                    logging.warning(f"Found {name} variable ({value}), but the method of detecting the latest version hasn't been defined")
                    continue

                func = globals()[f"version_{__apps[appname]['type']}"]
                args = deepcopy(__apps[appname])
                del args['type']

                old_version = value
                new_version = func(**args)

                if new_version is None:
                    logging.warning(f"Found {name} variable ({value}), but version detection returned nothing. Skipping...")
                    continue

                if old_version != new_version:
                    upgrades.append({
                        'name': name,
                        'value': value,
                        'comment': comment,
                        'appname': appname,
                        'old_version': old_version,
                        'new_version': new_version,
                    })

    for i in range(len(lines)):
        groups = search.match(lines[i])
        if groups is None:
            continue

        name = groups.group('name').strip(' \n')
        value = groups.group('value').strip(' \n')
        comment = groups.group('comment').strip(' \n')
        appname = name.replace('_VERSION', '').lower()
        old_version = ''
        new_version = ''

        if not name.endswith('_VERSION'):
            continue

        for item in upgrades:
            if item['name'] == name and item['value'] == value:
                old_version = item['old_version']
                new_version = item['new_version']
                break

        if old_version == '' and new_version == '':
            continue

        logging.info(f'Upgrading "{name}" from {old_version} to {new_version}')

        if item['comment'] != '':
            lines[i] = f'ARG {name}={new_version} # {comment}'
        else:
            lines[i] = f'ARG {name}={new_version}'

    if debug:
        for line in lines:
            print(line)
    else:
        with open(__dockerfile, 'w') as fd:
            for line in lines:
                fd.write(f'{line}\n')

if __name__ == '__main__':
    main()
