package Note::App;
use strict;
use warnings;

use vars qw();

use Moose;
use Module::Load;
use Module::Refresh;

use Note::Param;
no warnings qw(uninitialized);

has 'config' => (
	'is' => 'rw',
	'isa' => 'HashRef',
	'lazy' => 1,
	'default' => sub { return {}; },
);

has 'storage' => (
	'is' => 'rw',
	'isa' => 'HashRef',
	'default' => sub { return {}; },
);

has 'name' => (
	'is' => 'rw',
	'isa' => 'Str',
);

has 'root' => (
	'is' => 'rw',
	'isa' => 'Str',
);

# default, directory lookup dispatcher
sub dispatch
{
	my ($obj, $param) = get_param(@_);
	my $page = undef;
	my $root = $param->{'root'}. '/page';
	my $sp = join('/', @{$param->{'path'}});
	my $file = $root. ((length($sp)) ? '/'. $sp : '');
	if (-d $file)
	{
		$file .= '/_index';
	}
	$file .= '.njs';
	# load njs page file
	if (-e $file)
	{
		my $njs = new Note::File::JSON(
			'file' => $file,
		);
		$njs->read_file();
		my $data = $njs->data();
		$param->{'file'} = $file;
		$param->{'data'} = $data;
		if (defined $data->{'class'})
		{
			my $pgclass = $data->{'class'};
			# read perl package for class
			load($pgclass);

			# refresh module for development
			my $classpath = $pgclass. '.pm';
			$classpath =~ s/::/\//g;
			Module::Refresh->refresh_module($classpath);

			# create instance
			$page = $pgclass->new($param);
		}
		else
		{
			$page = new Note::Page($param);
		}
	}
	else
	{
		#die('File not found: '. $sp);
		return undef;
	}
	return $page;
}

1;

