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
use Note::Data::Model;
use Note::App;
use Note::File::RDF;
use Note::RDF::Class;

my $fp = 'test.rdb';
if (-e $fp)
{
	unlink($fp);
}
my $fstore = new Note::File::RDF(
	'file' => $fp,
);

my $rdf = $fstore->rdf();
$rdf->add_statement(iri('http://someuri/1'), ns_iri('rdf', 'type'), iri('http://otheruri/1'));

Note::RDF::Class::create({
	'rdf' => $rdf,
	'id' => ns_iri('note', 'class/type'),
});

my $cl = Note::RDF::Class::create({
	'rdf' => $rdf,
	'id' => ns_iri('note', 'class/object'),
});

$cl->add_property(
	'id' => ns_iri('note', 'field/object/type'),
)->add_range(
	'class' => ns_iri('note', 'class/type'),
);

$cl->add_property(
	'id' => ns_iri('note', 'field/object/label'),
)->add_range(
	'class' => ns_iri('xsd', 'string'),
);

::log($fstore->model(), $cl->get_properties('uri_only' => 1));

