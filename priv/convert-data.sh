#!/usr/bin/env bash

################################################################################
# given a path to a json line file like
# {"id":100
# ,"name":"test_user_0000010"
# ,"email":"test_user_0000010@test.local"
# ,"access_token":"M38KP6UN3H8IMA2L7HBK3LREEIR8CIR4JC5US0BRJPP37QSMLRGG"
# ,"refresh_token":"9D6OCEETHGPN9KQ4ICDEE4DQU7Q2GASLI6QVARLQO8GUGR8A0FDG"
# }
# produced by mix teiserver.ensure_test_users <user_admin_token> 10000
#
# convert everything and dump it into a 'test-users.sqlite' sqlite db
################################################################################

set -euo pipefail

jq -r 'to_entries | map(.value) | @csv' <"$1" >/tmp/test-users.csv

sqlite3 test-users.sqlite <<EOF
CREATE TABLE IF NOT EXISTS test_user
(
  id INTEGER
  , name TEXT
  , email TEXT
  , access_token TEXT
  , refresh_token TEXT
);

DELETE from test_user;

.mode csv
.import /tmp/test-users.csv test_user
EOF

rm /tmp/test-users.csv
