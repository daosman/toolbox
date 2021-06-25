# -*- mode: perl; indent-tabs-mode: nil; perl-indent-level: 4 -*-
# vim: autoindent tabstop=4 shiftwidth=4 expandtab softtabstop=4 filetype=perl

package toolbox::json;

use Data::Dumper;
use JSON::XS;
use JSON::Validator;
use IO::Compress::Xz;
use IO::Uncompress::UnXz;
use toolbox::logging;

use Exporter qw(import);
our @EXPORT = qw(put_json_file get_json_file open_write_text_file open_read_text_file);

use strict;
use warnings;

sub open_write_text_file {
    my $filename = shift;
    chomp $filename;
    my $rc = 0;
    if (! defined $filename) {
        # filename not defined
        $rc = 1;
    }
    if ($filename =~ /\.xz$/) {
        debug_log(sprintf "open_write_text_file(): file [%s] already named for compression\n", $filename);
    } else {
        # Always default to compression when writing
        $filename .= ".xz";
        debug_log(sprintf "open_write_text_file(): changed filename to [%s]\n", $filename);
    }
    debug_log(sprintf "open_write_text_file(): trying to open [%s] for writing\n", $filename);
    my $fh = new IO::Compress::Xz $filename;
    if (! defined $fh) {
        # cannot open file;
        $rc = 3;
    }
    return ($fh, $rc);
}

sub open_read_text_file {
    my $filename = shift;
    my $rc = 0;
    chomp $filename;
    if (! defined $filename) {
        # filename not defined
        $rc = 1;
    }
    if (-e $filename . ".xz") {
        if (-e $filename) {
            debug_log(sprintf "open_read_text_file(): both [%s] and [%s] exist, reading [%s]\n", $filename, $filename . ".xz", $filename . ".xz");
        }
        $filename .= ".xz";
    } elsif (! -e $filename ) {
        # file not found
        $rc = 2;
    }
    debug_log(sprintf "open_read_text_file(): trying to open [%s]\n", $filename);
    my $fh = new IO::Uncompress::UnXz $filename, Transparent => 1;
    if (! defined $fh) {
        # cannot open file
        $rc = 3;
    }
    return ($fh, $rc);
}

sub validate_schema {
    my $schema_filename = shift;
    my $filename = shift;
    my $json_ref = shift;
    if (defined $schema_filename) {
        chomp $schema_filename;
        my $jv = JSON::Validator->new;
        (my $schema_fh, my $rc) = open_read_text_file($schema_filename);
        if ($rc == 0 and defined $schema_fh) {
            my $json_schema_text;
            while ( <$schema_fh> ) {
                $json_schema_text .= $_;
            }
            close($schema_fh);
            chomp $json_schema_text;
            if ($jv->schema($json_schema_text)) {
                debug_log(sprintf "validate_schema() going to validate schema with [%s]\n", $schema_filename);
                my @errors = $jv->validate($json_ref);
                if (scalar @errors >  0) {
                    printf "validate_schema(): validation errors for file %s with schema %s:\n", $filename, $schema_filename;
                    print Dumper \@errors;
                    debug_log("validate_schema(): data validation failed");
                    return 5;
                } else {
                    return 0;
                }
            } else {
                debug_log("validate_schema(): schema invalid");
                return 4;
            }
        } elsif ($rc == 1) {
            debug_log("validate_schema(): schema file name undefined");
            return 1;
        } elsif ($rc == 2) {
            debug_log("validate_schema(): schema file not found");
            return 2;
        } elsif ($rc == 3) {
            debug_log("validate_schema(): cannot open schema file");
            return 3;
        }
    } else {
        return 0;
    }
}

sub put_json_file {
    my $filename = shift;
    chomp $filename;
    my $json_ref = shift;
    my $schema_filename = shift;
    my $coder = JSON::XS->new->canonical->pretty;
    my $result = validate_schema($schema_filename, $filename, $json_ref);
    if ($result == 0) {
        debug_log("put_json_file(): validate_schema passed");
        my $json_text = $coder->encode($json_ref);
        if (! defined $json_text) {
            debug_log("put_json_file(): data json invalid");
            return 6;
        }
        (my $json_fh, my $rc) = open_write_text_file($filename);
        if ($rc == 0 and defined $json_fh) {
            printf $json_fh "%s", $json_text;
            close($json_fh);
            return 0;
        } elsif ($rc == 1) {
            debug_log("put_json_file(): data file name undefined");
            return 7;
        } elsif ($rc == 3) {
            debug_log("put_json_file(): cannot open data file");
            return 9;
        } else {
            debug_log("put_json_file(): error, something else");
            return $rc;
        }
    } elsif ($result == 1) {
        debug_log("put_json_file(): schema file name undefined");
        return 1
    } elsif ($result == 2) {
        debug_log("put_json_file(): schema file not found");
        return 2;
    } elsif ($result == 3) {
        debug_log("put_json_file(): cannot open schema file");
        return 3;
    } elsif ($result == 4) {
        debug_log("put_json_file(): schema invalid");
        return 4;
    } elsif ($result == 4) {
        debug_log("put_json_file(): validation failed");
        return 5;
    } else {
        debug_log("put_json_file(): something else");
        return $result;
    }
}

sub get_json_file {
    my $filename = shift;
    my $schema_filename = shift;
    chomp $filename;
    my $json_ref;
    my $coder = JSON::XS->new;
    (my $json_fh, my $rc) = open_read_text_file($filename);
    if ($rc == 0 and defined $json_fh) {
        my $json_text = "";
        while ( <$json_fh> ) {
            $json_text .= $_;
        }
        close($json_fh);
        chomp $json_text;
        my $json_ref = $coder->decode($json_text);
        if (not defined $json_ref) {
            debug_log("get_json_file(): data json invalid");
            return ($json_ref, 6);
        }
        my $result = validate_schema($schema_filename, $filename, $json_ref);
        if ($result == 0) {
            return ($json_ref, 0);
        } elsif ($result == 1) {
            debug_log("get_json_file(): schema file undefined");
            return ($json_ref, 1);
        } elsif ($result == 2) {
            debug_log("get_json_file(): schema not found");
            return ($json_ref, 2);
        } elsif ($result == 3) {
            debug_log("get_json_file(): cannot open schema file");
            return ($json_ref, 3);
        } elsif ($result == 4) {
            debug_log("get_json_file(): schema invalid");
            return ($json_ref, 4);
        } elsif ($result == 5) {
            debug_log("get_json_file(): validation failed");
            return ($json_ref, 5);
        } else {
            debug_log("get_json_file(): error, something else");
            return ($json_ref, $result);
        }
    } elsif ($rc == 1) {
        debug_log("get_json_file(): data file name undefined");
        return ($json_ref, 7);
    } elsif ($rc == 2) {
        debug_log("get_json_file(): data file not found");
        return ($json_ref, 8);
    } elsif ($rc == 3) {
        debug_log("get_json_file(): cannot open data file");
        return ($json_ref, 9);
    } else {
        debug_log("get_json_file(): something else");
        return ($json_ref, $rc);
    }
}

1;
