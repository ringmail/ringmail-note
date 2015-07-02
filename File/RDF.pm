package Note::File::RDF;
use strict;
use warnings;
no warnings 'uninitialized';

use Moose;
use RDF::Trine::Model;
use RDF::Trine::Store;
use RDF::Trine::Store::DBI::SQLite;

use Note::File;
use Note::RDF::Sparql;

use base 'Note::File';

has 'type' => (
	'is' => 'rw',
	'isa' => 'Str',
	'default' => sub { return 'Store::DBI::SQLite'; },
);

has 'rdf' => (
	'is' => 'rw',
	'isa' => 'Note::RDF::Sparql',
	'lazy' => 1,
	'default' => sub {
		my $obj = shift;
		my $spq = new Note::RDF::Sparql(
			'storage' => $obj->store(),
		);
	},
);

has 'model' => (
	'isa' => 'RDF::Trine::Model',
	'is' => 'rw',
	'lazy' => 1,
	'default' => sub {
		my $obj = shift;
		return new RDF::Trine::Model($obj->store());
	},
);

has 'store' => (
	'is' => 'rw',
	'isa' => 'RDF::Trine::Store',
	'lazy' => 1,
	'default' => sub {
		my ($obj) = @_;
		my $type = $obj->type();
		if ($type eq 'Store::DBI::SQLite')
		{
			my $file = $obj->file();
			my $store = new RDF::Trine::Store({
				'storetype' => 'DBI',
				'name' => 'model',
				'dsn' => "dbi:SQLite:dbname=$file",
				'username' => '',
				'password' => '',
			});
			return $store;
		}
		die(qq|Invalid store type: '$type'|);
	},
);

1;

