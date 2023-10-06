#! /usr/bin/env python3

import os, sys, json, urllib
from urllib.request import urlopen

def main():
    url = sys.argv[1]
    device_path = sys.argv[2]

    # fetch json from usrl with device extension
    json_url = urllib.parse.urljoin(url+'/', device_path+'/')
    with urlopen(json_url) as response:
        data = json.loads(response.read().decode())
        files = data['files']
        chosen = [f for f in files if f['Url'].endswith('swu') or f['Url'].endswith('uuu')]
        print(' '.join([f['Url'] for f in chosen]))


if __name__ == "__main__":
    main()