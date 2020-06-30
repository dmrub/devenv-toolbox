#!/usr/bin/env python3
import sys
import configparser
import shlex
import json

def is_sequence(val):
    return isinstance(val, (list, tuple))


if __name__ == '__main__':
    if len(sys.argv) <= 1:
        print('Usage: {} config-file'.format(sys.argv[0]), file=sys.stderr)
        print('Parse config file and convert to POSIX shell configuration', file=sys.stderr)
        sys.exit(1)

    cfg_file = sys.argv[1]
    cfg_parser = configparser.ConfigParser()
    cfg_parser.read(cfg_file)
    for section in cfg_parser.sections():
        for key, value in cfg_parser.items(section):
            # replace characters not supported by bash in variable names
            for c in '^°!"§$%&/()[]{}=?;:,.-<>|\'':
                key = key.replace(c, '_')
            v = value.strip()
            if v.startswith('[') or v.startswith('"'):
                try:
                    value = json.loads(value)
                except json.JSONDecodeError:
                    pass
            shell_var = '{}_{}'.format(section.upper(), key.upper())
            if is_sequence(value):
                print("{}=({})".format(shell_var, ' '.join([shlex.quote(item) for item in value])))
            else:
                print("{}={}".format(shell_var, shlex.quote(value)))
