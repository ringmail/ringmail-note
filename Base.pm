package Note::Base;
use strict;
use warnings;

$Note::Config::File = '/home/note/cfg/note.cfg';
require Note::Config;

use vars qw(@ISA @EXPORT);

use Note::Log;
use Note::Row;
use Note::SQL::Table 'sqltable', 'transaction';

require Exporter;
@ISA = qw(Exporter);
@EXPORT = qw(sqltable transaction);

1;

