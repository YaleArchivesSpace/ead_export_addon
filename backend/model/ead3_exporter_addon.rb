# encoding: utf-8

class EAD3Serializer < EADSerializer
  serializer_for :ead3

  # keep AS IS during upgrade.  discuss upgrade to core that would put the date expression for "structured" dates in altrender, not in a sibling date record that is unlinked.
  def serialize_dates(obj, xml, fragments)
    add_unitdate = Proc.new do |value, context, fragments, atts={}|
      context.unitdate(atts) {
        sanitize_mixed_content( value, context, fragments )
      }
    end

    obj.dates.each do |date|
      next if date["publish"] === false && !@include_unpublished

      date_atts = {
        certainty: date['certainty'] ? date['certainty'] : nil,
        era: date['era'] ? date['era'] : nil,
        calendar: date['calendar'] ? date['calendar'] : nil,
        audience: date['publish'] === false ? 'internal' : nil
      }

      unless date['date_type'].nil?
        date_atts[:unitdatetype] = date['date_type'] == 'bulk' ? 'bulk' : 'inclusive'
      end

      date_atts.delete_if { |k,v| v.nil? }

      if date['begin'] || date['end']

        xml.unitdatestructured(date_atts) {

          if date['date_type'] == 'single' && date['begin']

            xml.datesingle( { standarddate: date['begin'] } ) {
              value = date['expression'].nil? ? date['begin'] : date['expression']
              xml.text(value)
            }

          else

            xml.daterange() {
              if date['begin']
                xml.fromdate( { standarddate: date['begin'] } ) {
                  xml.text(date['begin'])
                }
              end
              if date['end']
                xml.todate( { standarddate: date['end'] } ) {
                  xml.text(date['end'])
                }
              end
            }
          end
          #no need to have two sibling dates for the same ASpace date, so i'm moving this element up.
          #now we'll know, unambiguously, when two dates are actually one in the same (since they'll be bundled together)...
          #and we will post-process this unitdatestructured/unitdate invalidity (rather than have to try to compare siblings that may or may not have originated from the same ASpace date subrecord.)
          if date['expression']
            add_unitdate.call(date['expression'], xml, fragments, date_atts)
          end
        }

      elsif date['expression']
        add_unitdate.call(date['expression'], xml, fragments, date_atts)
      end

    end

  end

  # use new def from EAD2002 once we upgrade, but add back in the URIs.
  def serialize_child(data, xml, fragments, c_depth = 1)
    begin
    return if data["publish"] === false && !@include_unpublished
    return if data["suppressed"] === true

    tag_name = @use_numbered_c_tags ? :"c#{c_depth.to_s.rjust(2, '0')}" : :c

    atts = {:level => data.level, :otherlevel => data.other_level, :id => prefix_id(data.ref_id), :altrender => data.uri}

    if data.publish === false
      atts[:audience] = 'internal'
    end

    atts.reject! {|k, v| v.nil?}
    xml.send(tag_name, atts) {

      xml.did {
        if (val = data.title)
          xml.unittitle {  sanitize_mixed_content( val,xml, fragments) }
        end

        if !data.component_id.nil? && !data.component_id.empty?
          xml.unitid data.component_id
        end

        if @include_unpublished
          data.external_ids.each do |exid|
            xml.unitid  ({ "audience" => "internal",  "type" => exid['source'], "identifier" => exid['external_id']}) { xml.text exid['external_id']}
          end
        end

        serialize_origination(data, xml, fragments)
        serialize_extents(data, xml, fragments)
        serialize_dates(data, xml, fragments)
        serialize_did_notes(data, xml, fragments)

        EADSerializer.run_serialize_step(data, xml, fragments, :did)

        data.instances_with_sub_containers.each do |instance|
          serialize_container(instance, xml, @fragments)
        end

        if @include_daos
          data.instances_with_digital_objects.each do |instance|
            serialize_digital_object(instance['digital_object']['_resolved'], xml, fragments)
          end
        end
      }

      serialize_nondid_notes(data, xml, fragments)

      serialize_bibliographies(data, xml, fragments)

      serialize_indexes(data, xml, fragments)

      serialize_controlaccess(data, xml, fragments)

      EADSerializer.run_serialize_step(data, xml, fragments, :archdesc)

      data.children_indexes.each do |i|
        xml.text(
                 @stream_handler.buffer {|xml, new_fragments|
                   serialize_child(data.get_child(i), xml, new_fragments, c_depth + 1)
                 }
                 )
      end
    }
    rescue => e
      xml.text "ASPACE EXPORT ERROR : YOU HAVE A PROBLEM WITH YOUR EXPORT OF ARCHIVAL OBJECTS. THE FOLLOWING INFORMATION MAY HELP:\n
                MESSAGE: #{e.message.inspect}  \n
                TRACE: #{e.backtrace.inspect} \n "
    end
  end

  # use new def, but keep the URI on archdesc altrender after the upgrade
  def stream(data)
  @stream_handler = ASpaceExport::StreamHandler.new
  @fragments = ASpaceExport::RawXMLHandler.new
  @include_unpublished = data.include_unpublished?
  @include_daos = data.include_daos?
  @use_numbered_c_tags = data.use_numbered_c_tags?
  @id_prefix = I18n.t('archival_object.ref_id_export_prefix', :default => 'aspace_')

  builder = Nokogiri::XML::Builder.new(:encoding => "UTF-8") do |xml|
    begin

    ead_attributes = {}

    if data.publish === false
      ead_attributes['audience'] = 'internal'
    end

    xml.ead( ead_attributes ) {

      xml.text (
        @stream_handler.buffer { |xml, new_fragments|
          serialize_control(data, xml, new_fragments)
        }
      )

      atts = {:level => data.level, :otherlevel => data.other_level, :altrender => data.uri}
      atts.reject! {|k, v| v.nil?}

      xml.archdesc(atts) {

        xml.did {

          unless data.title.nil?
            xml.unittitle { sanitize_mixed_content(data.title, xml, @fragments) }
          end

          xml.unitid (0..3).map{ |i| data.send("id_#{i}") }.compact.join('.')

          unless data.repo.nil? || data.repo.name.nil?
            xml.repository {
              xml.corpname {
                xml.part {
                  sanitize_mixed_content(data.repo.name, xml, @fragments)
                }
              }
            }
          end

          unless data.language.nil?
            xml.langmaterial {
              xml.language(:langcode => data.language) {
                xml.text I18n.t("enumerations.language_iso639_2.#{ data.language }", :default => data.language)
              }
            }
          end

          data.instances_with_sub_containers.each do |instance|
            serialize_container(instance, xml, @fragments)
          end

          serialize_extents(data, xml, @fragments)

          serialize_dates(data, xml, @fragments)

          serialize_did_notes(data, xml, @fragments)

          serialize_origination(data, xml, @fragments)

          if @include_unpublished
            data.external_ids.each do |exid|
              xml.unitid  ({ "audience" => "internal", "type" => exid['source'], "identifier" => exid['external_id']}) { xml.text exid['external_id']}
            end
          end


          EADSerializer.run_serialize_step(data, xml, @fragments, :did)

        }# </did>

        serialize_nondid_notes(data, xml, @fragments)

        data.digital_objects.each do |dob|
              serialize_digital_object(dob, xml, @fragments)
        end

        serialize_bibliographies(data, xml, @fragments)

        serialize_indexes(data, xml, @fragments)

        serialize_controlaccess(data, xml, @fragments)

        EADSerializer.run_serialize_step(data, xml, @fragments, :archdesc)

        xml.dsc {

          data.children_indexes.each do |i|
            xml.text( @stream_handler.buffer {
              |xml, new_fragments| serialize_child(data.get_child(i), xml, new_fragments)
              }
            )
          end
        }
      }
    }

    rescue => e
      xml.text  "ASPACE EXPORT ERROR : YOU HAVE A PROBLEM WITH YOUR EXPORT OF YOUR RESOURCE. THE FOLLOWING INFORMATION MAY HELP:\n
                MESSAGE: #{e.message.inspect}  \n
                TRACE: #{e.backtrace.inspect} \n "
    end

  end


  # Add xml-model for rng
  # Make this conditional if XSD or DTD are requested
  xmlmodel_content = 'href="https://raw.githubusercontent.com/SAA-SDT/EAD3/master/ead3.rng"
    type="application/xml" schematypens="http://relaxng.org/ns/structure/1.0"'

  xmlmodel = Nokogiri::XML::ProcessingInstruction.new(builder.doc, "xml-model", xmlmodel_content)

  builder.doc.root.add_previous_sibling(xmlmodel)

  builder.doc.root.add_namespace nil, 'http://ead3.archivists.org/schema/'

  Enumerator.new do |y|
    @stream_handler.stream_out(builder, @fragments, y)
  end

end # END stream


  # use new def once we upgrade, but add back user_defined.string_2
  def serialize_control(data, xml, fragments)
    control_atts = {
      repositoryencoding: "iso15511",
      countryencoding: "iso3166-1",
      dateencoding: "iso8601",
      relatedencoding: "marc",
      langencoding: "iso639-2b",
      scriptencoding: "iso15924"
    }.reject{|k,v| v.nil? || v.empty? || v == "null"}

    xml.control(control_atts) {

      recordid_atts = {
        instanceurl: data.ead_location
      }

      otherrecordid_atts = {
        localtype: "BIB"
      }

      xml.recordid(recordid_atts) {
        xml.text(data.ead_id)
      }

      if data.user_defined['string_2']
        xml.otherrecordid(otherrecordid_atts) {
          xml.text(data.user_defined['string_2'])
        }
      end

      xml.filedesc {

        xml.titlestmt {
          # titleproper
          titleproper = ""
          titleproper += "#{data.finding_aid_title} " if data.finding_aid_title
          titleproper += "#{data.title}" if ( data.title && titleproper.empty? )
          xml.titleproper {  strip_tags_and_sanitize(titleproper, xml, fragments) }

          # titleproper (filing)
          unless data.finding_aid_filing_title.nil?
            xml.titleproper("localtype" => "filing") {
              sanitize_mixed_content(data.finding_aid_filing_title, xml, fragments)
            }
          end

          # subtitle
          unless data.finding_aid_subtitle.nil?
            xml.subtitle {
              sanitize_mixed_content(data.finding_aid_subtitle, xml, fragments)
            }
          end

          # author
          unless data.finding_aid_author.nil?
            xml.author {
              sanitize_mixed_content(data.finding_aid_author, xml, fragments)
            }
          end

          # sponsor
          unless data.finding_aid_sponsor.nil?
            xml.sponsor {
              sanitize_mixed_content( data.finding_aid_sponsor, xml, fragments)
            }
          end
        }

        unless data.finding_aid_edition_statement.nil?
          xml.editionstmt {
            sanitize_mixed_content(data.finding_aid_edition_statement, xml, fragments, true )
          }
        end

        xml.publicationstmt {

          xml.publisher { sanitize_mixed_content(data.repo.name, xml, fragments) }

          repo_addresslines = data.addresslines_keyed

          unless repo_addresslines.empty?
            xml.address {

              repo_addresslines.each do |key, line|
                if ['telephone', 'email'].include?(key)
                  addressline_atts = { localtype: key }
                  xml.addressline(addressline_atts) {
                    sanitize_mixed_content(line, xml, fragments)
                  }
                else
                  xml.addressline { sanitize_mixed_content( line, xml, fragments) }
                end
              end

              if data.repo.url
                xml.addressline {
                  xml.ref ({ href: data.repo.url, linktitle: data.repo.url, show: "new" }) {
                    xml.text(data.repo.url)
                  }
                }
              end
            }
          end

          if (data.finding_aid_date)
            xml.date { sanitize_mixed_content( data.finding_aid_date, xml, fragments) }
          end

          num = (0..3).map { |i| data.send("id_#{i}") }.compact.join('.')
          unless num.empty?
            xml.num() {
              xml.text(num)
            }
          end

          if data.repo.image_url
            xml.p {
              xml.ptr ({
                href: data.repo.image_url,
                actuate: "onload",
                show: "embed"
              })
            }
          end
        }

        if (data.finding_aid_series_statement)
          xml.seriesstmt {
            sanitize_mixed_content( data.finding_aid_series_statement, xml, fragments, true )
          }
        end

        if ( data.finding_aid_note )
          xml.notestmt {
            xml.controlnote {
              sanitize_mixed_content( data.finding_aid_note, xml, fragments, true )
            }
          }
        end

      } # END filedesc


      xml.maintenancestatus( { value: 'derived' } )


      maintenanceagency_atts = {
        countrycode: data.repo.country
      }.delete_if { |k,v| v.nil? || v.empty? }

      xml.maintenanceagency(maintenanceagency_atts) {

        unless data.repo.org_code.nil?
          agencycode = data.repo.country ? "#{data.repo.country}-" : ''
          agencycode += data.repo.org_code
          xml.agencycode() {
            xml.text(agencycode)
          }
        end

        xml.agencyname() {
          xml.text(data.repo.name)
        }
      }


      unless data.finding_aid_language.nil?
        xml.languagedeclaration() {

          xml.language() {
            strip_tags_and_sanitize( data.finding_aid_language, xml, fragments )
          }

          xml.script({ scriptcode: "Latn" }) {
            xml.text('Latin')
          }

        }
      end


      unless data.finding_aid_description_rules.nil?
        xml.conventiondeclaration {
          xml.abbr {
            xml.text(data.finding_aid_description_rules)
          }
          xml.citation {
            xml.text(I18n.t("enumerations.resource_finding_aid_description_rules.#{ data.finding_aid_description_rules}"))
          }
        }
      end


      unless data.finding_aid_status.nil?
        xml.localcontrol( { localtype: 'findaidstatus'} ) {
          xml.term() {
            xml.text(data.finding_aid_status)
          }
        }
      end



      xml.maintenancehistory() {

        xml.maintenanceevent() {

          xml.eventtype( { value: 'derived' } ) {}
          xml.eventdatetime() {
            xml.text(DateTime.now.to_s)
          }
          xml.agenttype( { value: 'machine' } ) {}
          xml.agent() {
            xml.text("ArchivesSpace #{ ASConstants.VERSION }")
          }
          xml.eventdescription {
            xml.text("This finding aid was produced using ArchivesSpace on #{ DateTime.now.strftime('%A %B %e, %Y at %H:%M') }")
          }
        }


        if data.revision_statements.length > 0
          data.revision_statements.each do |rs|
            xml.maintenanceevent() {
              xml.eventtype( { value: 'revised' } ) {}
              xml.eventdatetime() {
                xml.text(rs['date'].to_s)
              }
              xml.agenttype( { value: 'unknown' } ) {}
              xml.agent() {}
              xml.eventdescription() {
                sanitize_mixed_content( rs['description'], xml, fragments)
              }
            }
          end
        end
      }

    }
  end # END serialize_control

  #in core now.  can remove once we upgrade in 2020.
  def escape_ampersands(content)
    # first, find any pre-escaped entities and "mark" them by replacing & with @@
    # so something like &lt; becomes @@lt;
    # and &#1234 becomes @@#1234

    content.gsub!(/&\w+;/) {|t| t.gsub('&', '@@')}
    content.gsub!(/&#\d{4}/) {|t| t.gsub('&', '@@')}
    content.gsub!(/&#\d{3}/) {|t| t.gsub('&', '@@')}

    # now we know that all & characters remaining are not part of some pre-escaped entity, and we can escape them safely
    content.gsub!('&', '&amp;')

    # 'unmark' our pre-escaped entities
    content.gsub!(/@@\w+;/) {|t| t.gsub('@@', '&')}
    content.gsub!(/@@#\d{4}/) {|t| t.gsub('@@', '&')}
    content.gsub!(/@@#\d{3}/) {|t| t.gsub('@@', '&')}

    # only allow predefined XML entities, otherwise convert ampersand so XML will validate
    valid_entities = ['&quot;', '&amp;', '&apos;', '&lt;', '&gt;']
    content.gsub!(/&\w+;/) { |t| valid_entities.include?(t) ? t : t.gsub(/&/,'&amp;') }

    return content
  end

#in core now.  can remove once we upgrade in 2020.
  def structure_children(content, parent_name = nil)

    # 4archon...
    content.gsub!("\n\t", "\n\n")

    content.strip!

    original_content = content

    content = escape_ampersands(content)

    valid_children = valid_children_of_unmixed_elements(parent_name)

    # wrap text in <p> if it isn't already
    p_wrap = lambda do |text|
      text.chomp!
      text.strip!
      if text =~ /^<p(\s|\/|>)/
        if !(text =~ /<\/p>$/)
          text += '</p>'
        end
      else
        text = "<p>#{ text }</p>"
      end
      return text
    end

    # this should only be called if the text fragment only has element children
    p_wrap_invalid_children = lambda do |text|
      text.strip!
      if valid_children
        fragment = Nokogiri::XML::DocumentFragment.parse(text)
        new_text = ''
        fragment.element_children.each do |e|
          if valid_children.include?(e.name)
            new_text << e.to_s
          else
            new_text << "<p>#{ e.to_s }</p>"
          end
        end
        return new_text
      else
        return p_wrap.call(text)
      end
    end

    if !has_unwrapped_text?(content)
      content = p_wrap_invalid_children.call(content)
    else
      return content if content.length < 1
      new_content = ''
      blocks = content.split("\n\n").select { |b| !b.strip.empty? }
      blocks.each do |b|
        if has_unwrapped_text?(b)
          new_content << p_wrap.call(b)
        else
          new_content << p_wrap_invalid_children.call(b)
        end
      end
      content = new_content
    end

    ## REMOVED 2018-09 - leaving here for future reference
    # first lets see if there are any &
    # note if there's a &somewordwithnospace , the error is EntityRef and wont
    # be fixed here...
    # if xml_errors(content).any? { |e| e.message.include?("The entity name must immediately follow the '&' in the entity reference.") }
    #   content.gsub!("& ", "&amp; ")
    # end
    # END - REMOVED 2018-09

    # in some cases adding p tags can create invalid markup with mixed content
    # just return the original content if there's still problems
    xml_errors(content).any? ? original_content : content
  end

#in core now.  can remove once we upgrade in 2020.
  def strip_p(content)
    content = escape_ampersands(content)
    content.gsub("<p>", "").gsub("</p>", "").gsub("<p/>", '')
  end

#in core now.  can remove once we upgrade in 2020.
  def sanitize_mixed_content(content, context, fragments, allow_p = false  )
    # remove smart quotes from text
    content = remove_smart_quotes(content)

    # br's should be self closing
    content = content.gsub("<br>", "<br/>").gsub("</br>", '')

    ## moved this to structure_children and strop_p for easier testablity
    ## leaving this reference here in case you thought it should go here
    # content = escape_ampersands(content)

    if allow_p
      content = structure_children(content, context.parent.name)
    else
      content = strip_p(content)
    end

    # convert & to @@ before generating XML fragments for processing
    content.gsub!(/&/,'@@')

    content = convert_ead2002_markup(content)

    # convert @@ back to & on return value
    content.gsub!(/@@/,'&')

    begin
      if ASpaceExport::Utils.has_html?(content)
        context.text( fragments << content )
      else
        context.text content.gsub("&amp;", "&") #thanks, Nokogiri
      end
    rescue
      context.cdata content
    end
  end

#in core now.  can remove once we upgrade in 2020.
  def strip_invalid_children_from_note_content(content, parent_element_name)
    # convert & to @@ before generating XML fragment for processing
    content.gsub!(/&/,'@@')
    fragment = Nokogiri::XML::DocumentFragment.parse(content)
    children = fragment.element_children

    if !children.empty?
      if valid_children = valid_children_of_mixed_elements(parent_element_name)
        children.each do |e|
          if !valid_children.include?(e.name) && e.inner_text
            e.replace( e.inner_text.gsub(/\s+/, ' ') )
          end
        end
      end
    end

    # convert @@ back to & on return value
    fragment.inner_html.gsub(/@@/,'&')
  end

end
