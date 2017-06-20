import os, sys, time
import logging
import logging.handlers

if len(sys.argv) > 1:
  LOGFILE = sys.argv[1]
else:
  LOGFILE = "/var/log/hue/hue_run_query"

if len(sys.argv) > 2:
  sys.path.insert(0, sys.argv[2])
else:
  sys.path.insert(0, '/opt/cloudera/parcels/CDH/lib/hue')

if len(sys.argv) > 3:
  username = sys.argv[3]
else:
  username = 'admin'

if len(sys.argv) > 4:
  query = sys.argv[4]
else:
  query = 'select count(*) from default.sample_07'

logrotatesize = 10
backupcount = 10
LOG = logging.getLogger()
format = logging.Formatter("%(asctime)s - %(name)s - %(levelname)s - %(message)s")
fh = logging.handlers.RotatingFileHandler(LOGFILE, maxBytes = (1048576 * logrotatesize), backupCount = backupcount)
fh.setFormatter(format)
LOG.addHandler(fh)
LOG.setLevel(logging.DEBUG)

from django.conf import settings
os.environ['DJANGO_SETTINGS_MODULE']='desktop.settings'
from beeswax.server import dbms
from beeswax.conf import HIVE_SERVER_HOST
from django.contrib.auth.models import User

LOG.debug("Running query: %s" % query)
LOG.debug("Running as user: %s" % username)

hue, created = User.objects.get_or_create(username=username)

LOG.debug("Running query host: %s" % HIVE_SERVER_HOST)

start = time.time()
db = dbms.get(hue)
db.get_querys()

executequery = query
query = db.execute_statement(executequery)

while True:
  ret = db.get_state(query.get_handle())
  LOG.debug("ret: %s" % ret)
  LOG.debug("ret.key: %s" % ret.key)
  if ret.key!='running':
    break
  time.sleep(1)
  LOG.debug("Waiting for query execution")

result = db.fetch(query.get_handle())

i=0
for row in result.rows():
  print row
  if i>100:
    break
  i += 1

LOG.debug(db.get_log(query.get_handle()))
end = time.time()
elapsed = (end - start) / 60
LOG.debug("Time elapsed (minutes): %.2f" % elapsed)

