package Note::File::JSON;
use strict;
use warnings;
no warnings 'uninitialized';

use Moose;
use JSON::XS;
use Note::Param;

has 'file' => (
	'is' => 'rw',
	'isa' => 'Str',
	'required' => 1,
);

has 'data' => (
	'is' => 'rw',
	'isa' => 'Ref',
	'default' => sub { return {}; },
);

sub exists
{
	my ($obj, $param) = get_param(@_);
	my $fn = $obj->file();
	return (-e $fn);
}

sub write_file
{
	my ($obj, $param) = get_param(@_);
	my $enc = JSON::XS->new()->ascii()->pretty()->allow_nonref()->canonical(1);
	my $data = $obj->data();
	my $json = $enc->encode($data);
	my $fn = $obj->file();
	open (my $fd, '>', $fn) or die ("Open(>$fn): $!");
	print $fd $json;
	close ($fd);
}

sub read_file
{
	my ($obj, $param) = get_param(@_);
	my $fn = $obj->file();
	open (my $fd, '<', $fn) or die ("Open(<$fn): $!");
	my $json = '';
	{
		local $/;
		$/ = undef;
		$json = <$fd>;
	}
	close ($fd);
	unless (length($json))
	{
		die("Invalid JSON data for file: $fn");
	}
	my $data = decode_json($json);
	$obj->data($data);
	return $data;
}

1;

