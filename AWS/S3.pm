package Note::AWS::S3;
use strict;
use warnings;

use vars qw();

use Moose;
use POSIX 'strftime';
use Net::Amazon::S3;
use Net::Amazon::S3::Client;
use URI::Escape qw( uri_escape_utf8 );
use URI;

use Note::Param;

no warnings qw(uninitialized);

has 'access_key' => (
	'is' => 'rw',
	'isa' => 'Str',
	'required' => 1,
);

has 'secret_key' => (
	'is' => 'rw',
	'isa' => 'Str',
	'required' => 1,
);

has 's3' => (
	'is' => 'rw',
	'isa' => 'Net::Amazon::S3',
	'lazy' => 1,
	'default' => sub {
		my $obj = shift;
		return new Net::Amazon::S3({
			'aws_access_key_id' => $obj->access_key(),
			'aws_secret_access_key' => $obj->secret_key(),
			'retry' => 1,
		});
	},
);

sub upload
{
	my ($obj, $param) = get_param(@_);
	my $file = $param->{'file'};
	my $type = $param->{'content_type'};
	my $k = $param->{'key'};
	my $s3 = $obj->s3();
	my $client = new Net::Amazon::S3::Client('s3' => $s3);
	my $bucket = $client->bucket('name' => $param->{'bucket'});
	my $args = {
		'key' => $k,
	};
	if (defined $type)
	{
		$args->{'content_type'} = $type;
	}
	if (defined $param->{'expires'})
	{
		$args->{'expires'} = $param->{'expires'};
	}
	#::log("Upload", $args);
	my $s3obj = $bucket->object(%$args);
	$s3obj->put_filename($file);
	#my $ok = $bucket->add_key_filename($k, $file, $args);
	#unless ($ok)
	#{
	#	die($s3->err(). ': '. $s3->errstr());
	#}
	#return $ok;
	return 1;
}

sub exists
{
	my ($obj, $param) = get_param(@_);
	my $file = $param->{'file'};
	my $k = $param->{'key'};
	if (defined $k)
	{
		my $s3 = $obj->s3();
		my $cli = new Net::Amazon::S3::Client('s3' => $s3);
		my $bk = $cli->bucket($param->{'bucket'});
		my $object = $bk->object(
			'key' => $k,
		);
		return $object->exists();
	}
	return undef;
}

sub download_url
{
	my ($obj, $param) = get_param(@_);
	$param->{'expire'} ||= time() + (60 * 60);
	my $k = $param->{'key'};
	if (defined $k)
	{
		my $s3 = $obj->s3();
		if (defined $param->{'filename'})
		{
			my $go = new Net::Amazon::S3::Request::GetObject(
				's3' => $s3,
				'bucket' => $param->{'bucket'},
				'key' => $k,
				'method' => 'GET',
			);
			my $rq = new Net::Amazon::S3::HTTPRequest(
				's3' => $s3,
				'method' => $go->method(),
				'headers' => {
					'response-content-disposition' => 'attachment; filename='. $param->{'filename'},
				},
				'path' => $go->_uri($k),
			);
			my $uri = _query_string($rq, $param->{'expire'});
			return $uri;
		}
		else
		{
			my $cli = new Net::Amazon::S3::Client('s3' => $s3);
			my $bk = $cli->bucket('name' => $param->{'bucket'});
			my $object = $bk->object(
				'key' => $k,
				'expires' => $param->{'expire'},
			);
			my $uri = $object->query_string_authentication_uri();
			return $uri;
		}
	}
	return undef;
}

sub _query_string
{
	my ( $self, $expires ) = @_;
	my $method = $self->method;
	my $path = $self->path;
	my $headers = $self->headers;
 
	my $aws_access_key_id = $self->s3->aws_access_key_id;
	my $aws_secret_access_key = $self->s3->aws_secret_access_key;
	my $canonical_string = _canonical_string( $self, $method, $path, $headers, $expires );
	my @hs = sort keys %$headers;
	if (scalar @hs)
	{
		$canonical_string .= '?';
		$canonical_string .= join('&', map {"$_=$headers->{$_}"} @hs);
	}
	my $encoded_canonical = $self->_encode( $aws_secret_access_key, $canonical_string );
	my $protocol = $self->s3->secure ? 'https' : 'http';
	my $uri = "$protocol://s3.amazonaws.com/$path";
	if ( $path =~ m{^([^/?]+)(.*)} && Net::Amazon::S3::HTTPRequest::_is_dns_bucket($1) ) {
		$uri = "$protocol://$1.s3.amazonaws.com$2";
	}
	$uri = URI->new($uri);
	foreach my $k (@hs)
	{
		$uri->query_param($k => $headers->{$k});
	}
	$uri->query_param( AWSAccessKeyId => $aws_access_key_id );
	$uri->query_param( Expires        => $expires );
	$uri->query_param( Signature      => $encoded_canonical );
	return $uri;
}

sub _canonical_string
{
	my ( $self, $method, $path, $headers, $expires ) = @_;
	my $METADATA_PREFIX      = 'x-amz-meta-';
	my $AMAZON_HEADER_PREFIX = 'x-amz-';
	my %interesting_headers = ();
	while ( my ( $key, $value ) = each %$headers ) {
		my $lk = lc $key;
		if (   $lk eq 'content-md5'
			or $lk eq 'content-type'
			or $lk eq 'date'
			or $lk =~ /^$AMAZON_HEADER_PREFIX/ )
		{
			$interesting_headers{$lk} = $self->_trim($value);
		}
	}

	# these keys get empty strings if they don't exist
	$interesting_headers{'content-type'} ||= '';
	$interesting_headers{'content-md5'}  ||= '';

	# just in case someone used this.  it's not necessary in this lib.
	$interesting_headers{'date'} = ''
		if $interesting_headers{'x-amz-date'};

	# if you're using expires for query string auth, then it trumps date
	# (and x-amz-date)
	$interesting_headers{'date'} = $expires if $expires;

	my $buf = "$method\n";
	foreach my $key ( sort keys %interesting_headers ) {
		if ( $key =~ /^$AMAZON_HEADER_PREFIX/ ) {
			$buf .= "$key:$interesting_headers{$key}\n";
		} else {
			$buf .= "$interesting_headers{$key}\n";
		}
	}

	# don't include anything after the first ? in the resource...
	$path =~ /^([^?]*)/;
	$buf .= "/$1";

	# ...unless there any parameters we're interested in...
	if ( $path =~ /[&?](acl|torrent|location|uploads|delete)($|=|&)/ ) {
		$buf .= "?$1";
	} elsif ( my %query_params = URI->new($path)->query_form ){
		#see if the remaining parsed query string provides us with any query string or upload id
		if($query_params{partNumber} && $query_params{uploadId}){
			#re-evaluate query string, the order of the params is important for request signing, so we can't depend on URI to do the right thing
			$buf .= sprintf("?partNumber=%s&uploadId=%s", $query_params{partNumber}, $query_params{uploadId});
		}
		elsif($query_params{uploadId}){
			$buf .= sprintf("?uploadId=%s",$query_params{uploadId});
		}
	}

	return $buf;
}

1;

