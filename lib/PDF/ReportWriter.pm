#!/usr/bin/perl

# (C) Daniel Kasak: dan@entropy.homelinux.org
# See COPYRIGHT file for full license

# See 'man PDF::ReportWriter' for full documentation ... or of course continue reading

use strict;

package PDF::ReportWriter;

use PDF::API2;
use Number::Format;

use constant mm		=> 72/25.4;		# 25.4 mm in an inch, 72 points in an inch
use constant in		=> 72;			# 72 points in an inch
use constant A4_x	=> 210 * mm;		# x points in an A4 page ( 595.2755 )
use constant A4_y	=> 297 * mm;		# y points in an A4 page ( 841.8897 )
use constant letter_x	=> 8.5 * in;		# x points in a letter page
use constant letter_y	=> 11 * in;		# y points in a letter page

BEGIN {
	$PDF::ReportWriter::VERSION = '0.2';
}

# Globals
my ( $page, $txt, $x, $y, $fields_def, $page_count, $cell_spacing, $page_width, $page_height, $line,
    $need_data_header, $page_footer_and_margin, @group_header_queue );

sub new {
		
	my ( $class, $self ) = @_;
	
	bless $self, $class;
	
	if ($self->{paper} eq "A4") {
		if ($self->{orientation} eq "portrait") {
			$page_width = A4_x;
			$page_height = A4_y;
		} elsif ($self->{orientation} eq "landscape") {
			$page_width = A4_y;
			$page_height = A4_x;
		} else {
			die "Unsupported orientation: " . $self->{orientation} . "\n";
		}
	} elsif ($self->{paper} eq "letter") {
		if ($self->{orientation} eq "portait") {
			$page_width = letter_x;
			$page_height = letter_y;
		} elsif ($self->{orientation} eq "landscape") {
			$page_width = letter_y;
			$page_height = letter_x;
		} else {
			die "Unsupported orientation: " . $self->{orientation} . "\n";
		}
	} else {
		die "Unsupported paper format: " . $self->{paper} . "\n";
	}
	
	# Create a new PDF document
	$self->{pdf} = PDF::API2->new;
	
	#Add requested fonts
	for my $font ( @{$self->{font_list}} ) {
		# Roman fonts are easy
		$self->{fonts}->{$font}->{Roman} = $self->{pdf}->corefont(			$font,			-encoding => 'latin1');
		# The rest are f'n ridiculous. Adobe either didn't think about this, or are just stoopid
		if ($font eq "Courier") {
			$self->{fonts}->{$font}->{Bold} = $self->{pdf}->corefont(		"Courier-Bold",		-encoding => 'latin1');
			$self->{fonts}->{$font}->{Italic} = $self->{pdf}->corefont(		"Courier-Oblique",	-encoding => 'latin1');
			$self->{fonts}->{$font}->{BoldItalic} = $self->{pdf}->corefont(		"Courier-BoldOblique",	-encoding => 'latin1');
		}
		if ($font eq "Helvetica") {
			$self->{fonts}->{$font}->{Bold} = $self->{pdf}->corefont(		"Helvetica-Bold",	-encoding => 'latin1');
			$self->{fonts}->{$font}->{Italic} = $self->{pdf}->corefont(		"Helvetica-Oblique",	-encoding => 'latin1');
			$self->{fonts}->{$font}->{BoldItalic} = $self->{pdf}->corefont(		"Helvetica-BoldOblique",-encoding => 'latin1');
		}
		if ($font eq "Times") {
			$self->{fonts}->{$font}->{Bold} = $self->{pdf}->corefont(		"Times-Bold",		-encoding => 'latin1');
			$self->{fonts}->{$font}->{Italic} = $self->{pdf}->corefont(		"Times-Italic",		-encoding => 'latin1');
			$self->{fonts}->{$font}->{BoldItalic} = $self->{pdf}->corefont(		"Times-BoldItalic",	-encoding => 'latin1');
		}
	}
	
	$self->{page_count} = -1; # new_page adds one to the count ... this allows us to start at zero
	$self->new_page;
	
	return $self;
	
}

sub render_data {
	
	my ( $self, $data ) = @_;
	
	$self->{data} = $data;
	
	$txt->fillcolor("black");
	
	# Complete field definitions ...
	# Calculate the positions of cell and text object anchors, cell and text widths, etc
	
	$cell_spacing = $self->{data}->{max_font_size} * .5;
	
	$page_footer_and_margin = 8 + $self->{y_margin}; # usually we multiply the font-size by 1.5 ( for cell borders ) but this gives too much y-space in this case
	
	$x = $self->{x_margin};
	
	for my $field_definition ( @{$self->{data}->{fields}} ) {
		$field_definition->{x_border} = $x;
		$field_definition->{x_text} = $x + $cell_spacing;
		$field_definition->{border_width} = ( $page_width - ( $self->{x_margin} * 2 ) ) * $field_definition->{percent} / 100;
		$field_definition->{text_width} = $field_definition->{border_width} - $self->{data}->{max_font_size};
		$x += $field_definition->{border_width};
	}
	
	# Same for the group header / footer definitions
	for my $group_definition ( @{$self->{data}->{groups}} ) {
		for my $group_type ( qw / header footer / ) {
			$x = $self->{x_margin};
			for my $field_definition ( @{$group_definition->{$group_type}} ) {
				$field_definition->{x_border} = $x;
				$field_definition->{x_text} = $x + $cell_spacing;
				$field_definition->{border_width} = ( $page_width - ( $self->{x_margin} * 2 ) ) * $field_definition->{percent} / 100;
				$field_definition->{text_width} = $field_definition->{border_width} - $self->{data}->{max_font_size};
				$x += $field_definition->{border_width};
			}
		}
		# Set all group values to a special character so we recogcise that we are entering a new value for each of them ...
		#  ... particularly the GrandTotal group
		$group_definition->{value} = "!";
	}
	
	my $no_group_footer = 1; # We don't want a group footer on the first run
	
	# Main loop
	for my $row ( @{$self->{data}->{data_array}} ) {
		
		# Check if we're entering a new group
		$need_data_header = 0;
		
		foreach my $group ( reverse @{$self->{data}->{groups}} ) {
			if ($group->{value} ne $$row[$group->{data_column}]) {
				if ( ! $no_group_footer  && scalar(@{$group->{footer}}) ) {
					$self->group_footer($group);
				}
				# Store new group value
				$group->{value} = $$row[$group->{data_column}];
				# Queue headers for rendering in the data cycle ... prevents rendering a header before the last group footer is done
				if (scalar(@{$group->{header}})) {
					push @group_header_queue, { group => $group, value => $$row[$group->{data_column}] };
				}
				$need_data_header = 1; # Remember that we need to render a data header afterwoods
			}
		}
		
		$self->render_row( $self->{data}->{fields}, $row, "data");
		
		$no_group_footer = 0; # Turn group footers on
		
	}
	
	# The final group footers will not have been triggered ( only happens when we get a *new* group ), so we do them now
	foreach my $group ( reverse @{$self->{data}->{groups}} ) {
		$self->group_footer($group);
	}
	
	# And finally the page footer
	$self->page_footer;
	
}

sub new_page {
	
	my $self = shift;
	
	$self->{page_count} ++;
	$self->{pages}[$self->{page_count}] = $self->{pdf}->page;
	
	# Create a reference to the above page ( ease strain on eyes )
	$page = $self->{pages}[$self->{page_count}];
	
	# Set page dimensions
	$page->mediabox($page_width, $page_height);
	
	# Create a new txt object for the page
	$txt = $page->text;
	$txt->fillcolor("black"); # *** TODO *** colour support
	
	# Set y to the top of the page
	$y = $page_height - $self->{y_margin} * 1.5;
	
	# Remember that we need to print a data header
	$need_data_header = 1;
	
	# Create a new gfx object for our lines
	$line = $page->gfx;
	$line->strokecolor("grey");
	
	$page_count ++;
	
}

sub group_header {
	
	# Renders a new group header
	
	my ( $self, $group, $value ) = @_;
	
	# Test if we should start a new page
	my $y_needed = $page_footer_and_margin + ( $self->{data}->{max_font_size} * 2 ) + ( $group->{header}->{font_size} * 2 );
	
	if ($y - $y_needed < 0) {
		$self->page_footer;
		$self->new_page;
	}
	
	$self->render_row($group->{header}, $group->{value}, "group_header");
	
	$y -= $group->{header}->{font_size} * 2;
	
}

sub group_footer {
	
	# Renders a new group footer
	
	my ( $self, $group ) = @_;
		
	# Test if we should start a new page
	my $y_needed = $page_footer_and_margin + ( $self->{data}->{font_size} * 2 ) + ( $group->{footer}->{font_size} * 2 );
	
	if ($y - $y_needed < 0) {
		$self->page_footer;
		$self->new_page;
	}
	
	$self->render_row($group->{footer}, $group->{value}, "group_footer");
	
	$y -= $group->{footer}->{font_size} * 2;
	
}

sub page_footer {
	
	# Renders a page footer - currently a DateTime stamp and a page number.
	
	my $self = shift;
	
	$txt->font( $self->{fonts}->{Times}->{Bold}, 8 );
	
	$txt->translate( $self->{x_margin} + $cell_spacing, $self->{y_margin} );
	$txt->text("Rendered on " . localtime time);
	
	$txt->translate( $page_width - $self->{x_margin} - $cell_spacing, $self->{y_margin} );
	$txt->text_right("Page " . $page_count);
	
}

sub render_row {
	
	my ( $self, $fields, $row, $type, $no_cell_border ) = @_;
	
	# $fields		- a hash of field definitions
	# $row		- the current row to render
	# $type		- possible values are:
	#				- header				- prints a row of field names
	#				- data				- prints a row of data
	#				- group_header		- prints a row of group header
	#				- group_footer		- prints a row of group footer
	
	my $y_needed;
	
	# Firstly trigger any group headers that we have queued, but ONLY if we're in a data cycle
	if ($type eq "data") {
		while ( my $queued_headers = pop @group_header_queue ) {
			$self->group_header( $queued_headers->{group}, $queued_headers->{value} );
		}
	}
	
	# Page Footer / New Page / Page Header if necessary
	if ( $y - (  ( $cell_spacing * 2 ) + $page_footer_and_margin ) < 0 ) {
			$self->page_footer;
			$self->new_page;
	}
	
	if ($type eq "data" && $need_data_header && !$self->{data}->{no_field_headers}) {
			$self->render_row( $fields, 0, "header", 1 );
	}
		
	# Render row
	my $field_counter = 0;
	
	for my $field ( @{$fields} ) {
		
		# Render Cell Borders
		if ( $self->{data}->{cell_borders}  && !$no_cell_border && ! ( $type eq "group_header" || $type eq "group_footer" ) ) {
			$line->move( $field->{x_border}, $y );
			$line->line( $field->{x_border} + $field->{border_width}, $y );
			$line->line( $field->{x_border} + $field->{border_width}, $y + $self->{data}->{max_font_size} * 1.5 );
			$line->line( $field->{x_border}, $y + $self->{data}->{max_font_size} * 1.5 );
			$line->line( $field->{x_border}, $y );
			$line->stroke;
		}
		
		# Figure out what we're putting into the current cell, and set the font
		my $string;
		
		# Set the font and size
		# We currently default to Bold if we're doing a header. We also check for an specific font for this field, or fall back on the report default
		if ($type eq "group_header" || $type eq "group_footer") {
			$txt->font( $self->{fonts}->{ ( $field->{font} || $self->{default_font} ) }->{Bold}, $field->{font_size} || $self->{default_font_size} );
		} else {
			$txt->font( $self->{fonts}->{ ( $field->{font} || $self->{default_font} ) }->{Roman}, $field->{font_size} || $self->{default_font_size } );
		}
		
		if ($type eq "header") {
			$string = $field->{name};
		} elsif ($type eq "data") {
			$string = $$row[$field_counter];
		} elsif ($type eq "group_header") {
			$string = $field->{text};
			$string =~ s/\?/$row/g;	# In the case of a group header, the $row variable is the group value
		} elsif ($type eq "group_footer") {
			if (exists($field->{aggregate_source})) {
				if ($field->{text} eq "GrandTotals") {
					$string = $self->{data}->{fields}[$field->{aggregate_source}]->{grand_aggregate_result};
				} else {
					$string = $self->{data}->{fields}[$field->{aggregate_source}]->{group_results}->{$field->{text}};
				}
			} else {
				$string =$field->{text};
			}
			$string =~ s/\?/$row/g; # In the case of a group footer, the $row variable is the group value
		}
		
		# Apply type formatting ( eg currency )
		if ( $field->{type} eq "currency" && $type ne "header" ) {
			my $dollar_formatter = new Number::Format(
													thousands_sep	=> ',',
													decimal_point	=> '.',
													decimal_fill		=> 1,
													int_curr_symbol	=> 'USD'
							  );
			$string = "\$" . $dollar_formatter->format_number($string);
		}
		
		# Make sure the current string fits inside the current cell
		while ($txt->advancewidth($string) > $field->{text_width}) {
			chop($string);
		}
		
		# Alignment
		if ($field->{align} eq "right") {
			$txt->translate ( $field->{x_text} + $field->{text_width}, $y + $cell_spacing );
			$txt->text_right($string);
		} elsif ($field->{align} eq "centre") {
			# Calculate the width of the string, and move to the right so there's an even gap at both sides, and render left-aligned from there
			my $string_width = $txt->advancewidth($string);
			my $x_offset = ( $field->{text_width} - $string_width ) / 2;
			my $x_anchor = $field->{x_text} + $x_offset;
			$txt->translate( $x_anchor, $y + $cell_spacing );
			$txt->text($string);
		} else {
			# Default alignment if left-aligned
			$txt->translate( $field->{x_text}, $y + $cell_spacing );
			$txt->text($string);
		}
		
		# Now perform aggregate functions if defined
		if ( $type eq "data" && $field->{aggregate_function} ) {
			if ($field->{aggregate_function} eq "sum") {
				for my $group ( @{$self->{data}->{groups}} ) {
					$field->{group_results}->{$group->{name}} += $$row[$field_counter];
				}
				$field->{grand_aggregate_result} += $$row[$field_counter];
			} elsif ($field->{aggregate_function} eq "count") {
				for my $group ( @{$self->{data}->{groups}} ) {
					$field->{group_results}->{$group->{name}} += 1;
				}
				$field->{grand_aggregate_result} += 1;
			}
		} 
		
		# If we have just printed a group footer, we have to reset the value to 0
		if ( $type eq "group_footer" ) {
			$field->{group_aggregate_result} = 0;
			if (exists($field->{aggregate_source})) {
				$self->{data}->{fields}[$field_counter]->{group_results}->{$field->{text}} = 0;
			}
		}
		
		$field_counter ++;
		
	}
	
	$y -= $self->{data}->{max_font_size} * 1.5;
	
}

sub save {
	my $self = shift;
	$self->{pdf}->saveas($self->{destination});
	$self->{pdf}->end();
}

1;

=head1 NAME

PDF::ReportWriter

=head1 SYNOPSIS

use PDF::ReportWriter;

my $fields = [
   {
      name                     => "Company",
      percent                  => 85,
      font_size                => 12,
      align                    => "left"
   },
   {
      name                     => "Amount",
      percent                  => 15,
      font_size                => 12,
      align                    => "right",
      aggregate_function       => "sum",
      type                     => "currency"
   }
 ];

my $group = [
   {
      name                     => "WeekOfMonth",
      data_column              => 2,
      header                   => [
                                                percent            => 100,
                                                font_size          => 12,
                                                align              => "right",
                                                text               => "Payments for week ?"
                                  ]
      footer                   => [
                                                percent            => 85,
                                                font_size          => 12,
                                                align              => "right",
                                                text               => "Total for week ?"
                                  ],
                                  [
                                                percent            => 15,
                                                font_size          => 12,
                                                align              => "right",
                                                aggregate_source   => 1,
                                                text               => "WeekOfMonth",
                                                type               => "currency"
                                  ]
   }
 ];

my $report_def = {
   destination                 => "cheques.pdf",
   paper                       => "A4",
   orientation                 => "portrait",
   font_list                   => [ "Times", "Courier" ],
   default_font                => "Times",
   default_font_size           => 12,
   x_margin                    => 100 * mm,
   y_margin                    => 100 * mm
 };

my $report = PDF::ReportWriter->new($report_def);

my $records = $dbh->selectall_arrayref(
   "select
      Company,
      round(Amount, 2) as Amount,
      case
         when date_format(DateReceived, '%d') between 1 and 7 then 1
         when date_format(DateReceived, '%d') between 8 and 14 then 2
         when date_format(DateReceived, '%d') between 15 and 21 then 3
         when date_format(DateReceived, '%d') between 22 and 28 then 4
        else 5
      end as WeekOfMonth,
      date_format(DateReceived, '%W, %e %b %Y') as FullDate,
      1 as LotOfOnes
   from
      Cheques
   where
      ( DateReceived between '$lower_date' and '$upper_date' )
      and ( Amount is not null and Amount!=0 )
   order by
      DateReceived");

my $data = {
   max_font_size               => 12,
   cell_borders                => 1,
   no_field_headers            => 1,
   fields                      => $fields,
   groups                      => $groups,
   data_array                  => $records
 };
       
$report->render_data($data);

$report->save;
        
system("gpdf cheques.pdf &");

=head1 DESCRIPTION

PDF::ReportWriter is designed to simplify the task of creating high-quality business reports, for archiving or printing.

All objects are rendered in cells which are defined as a percentage of the available width ( ie similar to HTML tables ).

=head1 FIELD DEFINITIONS

A field definition can have the following attributes

=head2 name

The 'name' is used when rendering field headers, which happens whenever a new group or page is started.
You can disable rendering of field headers by setting no_field_headers in your data definition ( see above example ).

=head2 percent

The width of the field, as a percentage of the total available width.
The actual width will depend on the paper definition ( size and orientation ) and the x_margin in your report_definition.

=head2 font

The font to use. In most cases, you would set up a report-wide default_font. Only use this setting to override the default.

=head2 font_size

The font size. Nothing special here...

=head2 align

Possible values are "left", "right" and "centre". Note the spelling of "centre". I'm Australian.

=head2 aggregate_function

Possible values are "sum" and "count". Setting this attribute will make PDF::ReportWriter carry out the selected function
and store the results ( attached to the field ) for later use in group footers.

=head2 type

The only possible value currrently is "currency".

=head1 GROUP DEFINITIONS

Groups have the following attributes:

=head2 name

The name is used to identify which value to use in rendering aggregate functions ( see aggregate_source, below ).
Also, a special name, "GrandTotals" will cause PDF::ReportWriter to fetch *Grand* totals instead of group totals.
This negates the need to have an extra column of data in your data_array with all the same value ... which
is the only other way I can see of 'cleanly' getting GrandTotal functionality.

=head2 data_column

The data_column refers to the column ( starting at 0 ) of the data_array that you want to group on.

=head2 header / footer

Group headers and footers are defined in a similar way to field definitions ( and rendered by the same code ).
The difference is that the cell definition is contained in the 'header' and 'footer' hashes, ie the header and footer hashes resemble a field hash.
Consequently, most attributes that work for field cells also work for group cells. Additional attributes in the header and footer hashes are:

=head2 aggregate_source

This is used to retrieve the results of an aggregate_function ( see above ).
*** NOTE *** You MUST ( currently ) define the 'text' of a cell as the group's *name* for this to work properly.
I'm working on removing thie requirement.

=head1 REPORT DEFINITION

Possible attributes for the report defintion are:

=head2 destination

The path to the destination ( the pdf that you want to create ).

=head2 paper

The only paper types currently supported are A4 and Letter. And I haven't tested Letter...

=head2 orientation

portrait or landscape

=head2 font_list

An array of font names ( from the corefonts supported by PDF::API2 ) to set up.
When you include a font 'family', a range of fonts ( roman, italic, bold, etc ) are created.

=head2 default_font

The name of the font type ( from the above list ) to use as a default ( ie if one isn't set up for a cell ).

=head2 default_font_size

The default font size to use if one isn't set up for a cell.

=head2 x_margin

The amount of space ( left and right ) to leave as a margin for the report.

=head2 y_margin

The amount of space ( top and bottom ) to leave as a margin for the report.

=head1 DATA DEFINITION

The data definition wraps up most of the previous definitions, apart from the report definition.
My goal ( with a future release ) is to support unlimited 'sections', which you'll be able to achieve
by passing new data definitions and calling the 'render' method. Currently this does not work, but
should not take too much to get it going.

Attributes for the data definition:

=head2 max_font_size

This is used to calculate the required height of each row.
I'm considering writing something to figure this out automatically,
but for now you'll have to set this value.

=head2 cell_borders

Whether to render cell borders or not.

=head2 no_field_headers

Set to disable rendering field headers when beginning a new page or group.

=head2 fields

This is your field definition hash, from above.

=head2 groups

This is your group definition hash, from above.

=head2 data_array

This is the data to render.


=head1 METHODS

=head2 new ( report_definition )

Object constructor. Pass the report definition in.

=head2 render_data ( data_definition )

Renders the data passed in. Currently I've only tested with a single data_definition being passed
and rendered, but the goal ( with a future release ) is to support rendering multiple data definitions
in a single report.

=head2 save

Saves the pdf file ( in the location specified in the report definition ).

=head1 AUTHORS

Dan <dan@entropy.homelinux.org>
