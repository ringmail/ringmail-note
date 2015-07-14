#!/usr/bin/perl
use lib '/home/note/lib';
use lib '/home/note/app/dev/lib';

$Note::Config::File = '/home/note/cfg/note.cfg';
require Note::Config;

use Data::Dumper;
use POSIX 'strftime';
use Carp::Always;
use RDF::Trine ('iri', 'statement', 'literal');

use Note::Log;
use Note::RDF::NS ('ns_iri');
use Note::RDF::Sparql;
use Note::File::RDF;
use Note::DBManager;

my $name = 'email';
my $rt = '/home/note/app/dev/work/sql/dyl2';
my $fp = $rt. '/'. $name. '.njs';

my $dbm = new Note::DBManager(
	'root' => $rt,
);

my $data = $dbm->json_load($fp);

my $rfile = 'dbm.rdf';
unlink($rfile) if (-e $rfile);
my $fstore = new Note::File::RDF(
	'file' => $rfile,
);

$dbm->to_rdf(
	'rdf' => $fstore->rdf(),
	'name' => $name,
	'data' => $data,
);

::log(
	$name,
	$data,
	$fstore->model(),
);

