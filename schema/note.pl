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

my $fp = 'note.rdb';
if (-e $fp)
{
	unlink($fp);
}
my $fstore = new Note::File::RDF(
	'file' => $fp,
);

my $rdf = $fstore->rdf();

my %class = ();

$class{'data/model'} = Note::RDF::Class::create({
	'rdf' => $rdf,
	'id' => ns_iri('note', 'class/data/model'),
});

$class{'data/field'} = Note::RDF::Class::create({
	'rdf' => $rdf,
	'id' => ns_iri('note', 'class/data/field'),
});

$class{'data/type'} = Note::RDF::Class::create({
	'rdf' => $rdf,
	'id' => ns_iri('note', 'class/data/type'),
});

$class{'data/enum'} = Note::RDF::Class::create({
	'rdf' => $rdf,
	'id' => ns_iri('note', 'class/data/enum'),
});

$class{'data/enum/item'} = Note::RDF::Class::create({
	'rdf' => $rdf,
	'id' => ns_iri('note', 'class/data/enum/item'),
});

$class{'data/model'}->add_property(
	'id' => ns_iri('note', 'attr/data/model/field'),
)->add_range(
	'class' => ns_iri('note', 'class/data/field'),
);

$class{'data/field'}->add_property(
	'id' => ns_iri('note', 'attr/data/field/type'),
)->add_range(
	'class' => ns_iri('note', 'class/data/type'),
);

$class{'data/field'}->add_property(
	'id' => ns_iri('note', 'attr/data/field/key'),
)->add_range(
	'class' => ns_iri('xsd', 'string'),
);

$class{'data/field'}->add_property(
	'id' => ns_iri('note', 'attr/data/field/label'),
)->add_range(
	'class' => ns_iri('xsd', 'string'),
);

$class{'data/field'}->add_property(
	'id' => ns_iri('note', 'attr/data/field/description'),
)->add_range(
	'class' => ns_iri('xsd', 'string'),
);

$class{'data/field'}->add_property(
	'id' => ns_iri('note', 'attr/data/field/null'),
)->add_range(
	'class' => ns_iri('xsd', 'boolean'),
);

$class{'data/field'}->add_property(
	'id' => ns_iri('note', 'attr/data/field/class'),
)->add_range(
	'class' => ns_iri('rdfs', 'Class'),
);

$class{'data/field'}->add_property(
	'id' => ns_iri('note', 'attr/data/field/length'),
)->add_range(
	'class' => ns_iri('note', 'class/data/enum'),
);

$class{'data/field'}->add_property(
	'id' => ns_iri('note', 'attr/data/field/length_specify'),
)->add_range(
	'class' => ns_iri('xsd', 'int'),
);

$class{'data/field'}->add_property(
	'id' => ns_iri('note', 'attr/data/field/default'),
)->add_range(
	'class' => ns_iri('rdfs', 'Resource'),
);

$class{'data/field'}->add_property(
	'id' => ns_iri('note', 'attr/data/field/timestamp'),
)->add_range(
	'class' => ns_iri('xsd', 'boolean'),
);

$rdf->add_statement(ns_iri('note', 'inst/data/type/ref'), ns_iri('rdf', 'type'), ns_iri('note', 'class/data/type'));
$rdf->add_statement(ns_iri('note', 'inst/data/type/text'), ns_iri('rdf', 'type'), ns_iri('note', 'class/data/type'));
$rdf->add_statement(ns_iri('note', 'inst/data/type/binary'), ns_iri('rdf', 'type'), ns_iri('note', 'class/data/type'));
$rdf->add_statement(ns_iri('note', 'inst/data/type/boolean'), ns_iri('rdf', 'type'), ns_iri('note', 'class/data/type'));
$rdf->add_statement(ns_iri('note', 'inst/data/type/integer'), ns_iri('rdf', 'type'), ns_iri('note', 'class/data/type'));
$rdf->add_statement(ns_iri('note', 'inst/data/type/float'), ns_iri('rdf', 'type'), ns_iri('note', 'class/data/type'));
$rdf->add_statement(ns_iri('note', 'inst/data/type/currency'), ns_iri('rdf', 'type'), ns_iri('note', 'class/data/type'));
$rdf->add_statement(ns_iri('note', 'inst/data/type/date'), ns_iri('rdf', 'type'), ns_iri('note', 'class/data/type'));
$rdf->add_statement(ns_iri('note', 'inst/data/type/datetime'), ns_iri('rdf', 'type'), ns_iri('note', 'class/data/type'));

::log($fstore->model());

