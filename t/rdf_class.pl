#!/usr/bin/perl
use lib '/home/note/lib';
use lib '/home/note/app/dev/lib';

$Note::Config::File = '/home/note/cfg/note.cfg';
require Note::Config;

use Data::Dumper;
use POSIX 'strftime';
use Carp::Always;
use RDF::Trine ('iri', 'statement', 'literal');
use Test::More;

use Note::Log;
use Note::RDF::NS ('ns_iri');
use Note::RDF::Sparql;
use Note::Data::Model;
use Note::App;
use Note::File::RDF;
use Note::RDF::Class;

# create work dir
my $root = 'work';
mkdir($root) unless ((-e $root) && (-d $root));

# remove temp file
my $fp = $root. '/test.rdb';
unlink($fp) if (-e $fp);

# create temp file
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

#::log(scalar($fstore->model()), $cl->get_properties('uri_only' => 1));

is_deeply(
	$cl->get_properties('uri_only' => 1),
	[
	  bless( [
			   'URI',
			   'http://note.atellix.com/v1/field/object/label'
			 ], 'RDF::Query::Node::Resource' ),
	  bless( [
			   'URI',
			   'http://note.atellix.com/v1/field/object/type'
			 ], 'RDF::Query::Node::Resource' )
	],
	'get_properties',
);

#::log($fstore->model()->as_hashref());
is_deeply(
	$fstore->model()->as_hashref(),
	{
		'http://someuri/1' => {
		'http://www.w3.org/1999/02/22-rdf-syntax-ns#type' => [
		{
		'value' => 'http://otheruri/1',
		'type' => 'uri'
		}
		]
		},
		'http://note.atellix.com/v1/field/object/type' => {
		'http://www.w3.org/2000/01/rdf-schema#domain' => [
		{
		'value' => 'http://note.atellix.com/v1/class/object',
		'type' => 'uri'
		}
		],
		'http://www.w3.org/1999/02/22-rdf-syntax-ns#type' => [
		{
		'value' => 'http://www.w3.org/1999/02/22-rdf-syntax-ns#Property',
		'type' => 'uri'
		}
		],
		'http://www.w3.org/2000/01/rdf-schema#range' => [
		{
		'value' => 'http://note.atellix.com/v1/class/type',
		'type' => 'uri'
		}
		]
		},
		'http://note.atellix.com/v1/field/object/label' => {
		'http://www.w3.org/2000/01/rdf-schema#domain' => [
		{
		'value' => 'http://note.atellix.com/v1/class/object',
		'type' => 'uri'
		}
		],
		'http://www.w3.org/1999/02/22-rdf-syntax-ns#type' => [
		{
		'value' => 'http://www.w3.org/1999/02/22-rdf-syntax-ns#Property',
		'type' => 'uri'
		}
		],
		'http://www.w3.org/2000/01/rdf-schema#range' => [
		{
		'value' => 'http://www.w3.org/2001/XMLSchema#string',
		'type' => 'uri'
		}
		]
		},
		'http://note.atellix.com/v1/class/type' => {
		'http://www.w3.org/1999/02/22-rdf-syntax-ns#type' => [
		{
		'value' => 'http://www.w3.org/2000/01/rdf-schema#Class',
		'type' => 'uri'
		}
		]
		},
		'http://note.atellix.com/v1/class/object' => {
		'http://www.w3.org/1999/02/22-rdf-syntax-ns#type' => [
		{
		'value' => 'http://www.w3.org/2000/01/rdf-schema#Class',
		'type' => 'uri'
		}
		]
		}
	},
	'rdf structure',
);

done_testing();

