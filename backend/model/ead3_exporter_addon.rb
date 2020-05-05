# encoding: utf-8

class EAD3Serializer < EADSerializer
  serializer_for :ead3


  # keep AS IS during upgrade.  discuss adding to core.  need those parts!
  def serialize_controlaccess(data, xml, fragments)

    if (data.controlaccess_subjects.length + data.controlaccess_linked_agents.length) > 0
      xml.controlaccess {

    ##### this uses data supplied by the helper.... but that smooshes everything into 'content'
    ##### we want to handle each term, though.
#        data.controlaccess_subjects.each do |node_data|
#
#          if node_data[:atts]['authfilenumber']
#            node_data[:atts]['identifier'] = node_data[:atts]['authfilenumber'].clone
#            node_data[:atts].delete('authfilenumber')
#          end

#          xml.send(node_data[:node_name], node_data[:atts]) {
#            xml.part() {
#              sanitize_mixed_content( node_data[:content], xml, fragments, ASpaceExport::Utils.include_p?(node_data[:node_name]) )
#          }
#      end
        data.subjects.each do |link|
          subject = link['_resolved']
          node_name = case subject['terms'][0]['term_type']
                when 'function'; 'function'
                when 'genre_form', 'style_period';  'genreform'
                when 'geographic'; 'geogname'
                when 'occupation';  'occupation'
                when 'topical', 'cultural_context'; 'subject'
                when 'uniform_title'; 'title'
                else; nil
              end
          terms = subject['terms']

          atts = {}
          atts['source'] = subject['source'] if subject['source']
          atts['identifier'] = subject['authority_id'] if subject['authority_id']

          next unless node_name

          xml.send(node_name, atts) {
            terms.each do |t|
              xml.part(:localtype => t['term_type']) {
                sanitize_mixed_content(t['term'], xml, fragments )
              }
            end
          }
        end

      ##### this is also bad, primarily because the helper file adds "fmo" to all agents linked as sources.
      ##### so, we'll start from scratch for here and make sure not to supply data that isn't there.... and also we'll split out terms into separate part elements.
      ##### and, last, since we could still get an empty controlaccess section if there's only an agent linked as a source, we'll remove empty controlaccess elements during our post-export EAD transformation.
      # data.controlaccess_linked_agents.each do |node_data|

      #   if node_data[:atts][:role]
      #    node_data[:atts][:relator] = node_data[:atts][:role]
      #      node_data[:atts].delete(:role)
      #    end

      #    if node_data[:atts][:authfilenumber]
      #      node_data[:atts][:identifier] = node_data[:atts][:authfilenumber].clone
      #      node_data[:atts].delete(:authfilenumber)
      #    end

      #    xml.send(node_data[:node_name], node_data[:atts]) {
      #      xml.part() {
      #      }
      #    }
      #  end
      data.linked_agents.each do |link|
        next if ['creator', 'source'].include? link['role'] || (link['_resolved']['publish'] == false && !@include_unpublished)

        terms = link['terms']

        relator = link['relator']

        agent = link['_resolved'].dup
        rules = agent['display_name']['rules']
        source = agent['display_name']['source']
        identifier = agent['display_name']['authority_id']

        agent_node_name = case agent['agent_type']
                    when 'agent_person'; 'persname'
                    when 'agent_family'; 'famname'
                    when 'agent_corporate_entity'; 'corpname'
                    when 'agent_software'; 'name'
                  end

        atts = {}
        atts[:relator] = relator if relator
        atts[:source] = source if source
        atts[:rules] = rules if rules
        atts[:identifier] = identifier if identifier
        atts[:audience] = 'internal' if link['_resolved']['publish'] == false

        primary_part_atts = {}
        primary_part_atts[:localtype] = agent['agent_type'] if agent['agent_type']

        next unless agent_node_name

        if identifier && (terms.length > 0)
          primary_part_atts[:identifier]  = atts[:identifier].clone
          atts.delete(:identifier)
        end

        xml.send(agent_node_name, atts) {
          xml.part(primary_part_atts) {
            sanitize_mixed_content(agent['title'], xml, fragments)
          }
          terms.each do |t|
            xml.part(:localtype => t['term_type']) {
              sanitize_mixed_content(t['term'], xml, fragments )
            }
          end
        }

      end

      } #</controlaccess>
    end
  end

  # keep AS IS during upgrade.  discuss adding to core.
  def serialize_origination(data, xml, fragments)
    unless data.creators_and_sources.nil?
      data.creators_and_sources.each do |link|
        agent = link['_resolved']
        #not sure why the EAD3 exporter capitalized "Creator", but not "Source".  let's capitalize both, since it's mapped to a lable (but should be a type)
        role = link['role'].capitalize()
        relator = link['relator']
        sort_name = agent['display_name']['sort_name']
        rules = agent['display_name']['rules']
        source = agent['display_name']['source']
        identifier = agent['display_name']['authority_id']
        # new part, should be in core. ALSO needs to be added to MARCXML exports (even more importantly)
        title = link['title']
        node_name = case agent['agent_type']
                    when 'agent_person'; 'persname'
                    when 'agent_family'; 'famname'
                    when 'agent_corporate_entity'; 'corpname'
                    when 'agent_software'; 'name'
                    end
        xml.origination(:label => role) {

          atts = {:relator => relator, :source => source, :rules => rules, :identifier => identifier}

          primary_part_atts = {}
          primary_part_atts[:localtype] = agent['agent_type'] if agent['agent_type']

          if identifier && title
            primary_part_atts[:identifier] = atts[:identifier].clone
            atts.delete(:identifier)
          end

          atts.reject! {|k, v| v.nil?}

          xml.send(node_name, atts) {
            xml.part(primary_part_atts) {
              sanitize_mixed_content(sort_name, xml, fragments)
            }
            #new part...  probably a better way to do this, but it works.
            if title
              xml.part(:localtype => 'title') {
                sanitize_mixed_content(title, xml, fragments)
              }
            end
          }
        }
      end
    end
  end

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
        audience: date['publish'] === false ? 'internal' : nil,
        label: date['label'] ? date['label'] : nil
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
          #i think we can "fix" this in the core, by just adding 'expression' to altrender when it's present on a structured date.
          if date['expression']
            add_unitdate.call(date['expression'], xml, fragments, date_atts)
          end
        }

      elsif date['expression']
        add_unitdate.call(date['expression'], xml, fragments, date_atts)
      end

    end

  end

  # keep AS IS during upgrade.  discuss upgrade to core, since why not include these access restrict values in the EAD???
  def serialize_note_content(note, xml, fragments)
    return if note["publish"] === false && !@include_unpublished
    audatt = note["publish"] === false ? {:audience => 'internal'} : {}
    content = note["content"]

    atts = {:id => prefix_id(note['persistent_id']) }.reject{|k,v| v.nil? || v.empty? || v == "null" }.merge(audatt)

    if note["type"] == 'accessrestrict' && note["rights_restriction"] && !note["rights_restriction"]["local_access_restriction_type"].empty?
      accessatt = {:localtype => note["rights_restriction"]["local_access_restriction_type"].join(' ')}
      atts = atts.merge(accessatt)
    end

    head_text = note['label'] ? note['label'] : I18n.t("enumerations._note_types.#{note['type']}", :default => note['type'])
    content, head_text = extract_head_text(content, head_text)
    xml.send(note['type'], atts) {
      xml.head { sanitize_mixed_content(head_text, xml, fragments) } unless ASpaceExport::Utils.headless_note?(note['type'], content )
      sanitize_mixed_content(content, xml, fragments, ASpaceExport::Utils.include_p?(note['type']) ) if content
      if note['subnotes']
        serialize_subnotes(note['subnotes'], xml, fragments, ASpaceExport::Utils.include_p?(note['type']))
      end
    }
  end

  # keep AS IS during upgrade.  adding URLs for top containers and locations.
  def serialize_container(inst, xml, fragments)
    atts = {}

    sub = inst['sub_container']
    top = sub['top_container']['_resolved']

    atts[:id] = prefix_id(SecureRandom.hex)
    last_id = atts[:id]

    atts[:localtype] = top['type']
    text = top['indicator']

    atts[:label] = I18n.t("enumerations.instance_instance_type.#{inst['instance_type']}",
                          :default => inst['instance_type'])

    if top['barcode']
      atts[:containerid] = "#{top['barcode']}"
    end

    # by default, container profiles are added to altrender.  we need to do something different, though
    # to keep all of our altrenders the same.
    # :altrender => data.uri
    if (cp = top['container_profile'])
      atts[:encodinganalog] = cp['_resolved']['url'] || cp['_resolved']['name']
    end

    # more new stuff
    atts[:altrender] = top['uri']

    if (locations = top['container_locations'])
      first_location = locations.select {|l| l['status'] == 'current'}.first
      atts[:altrender] += ' ' + first_location['ref'] if first_location
    end

    xml.container(atts) {
      sanitize_mixed_content(text, xml, fragments)
    }

    (2..3).each do |n|
      atts = {}

      next unless sub["type_#{n}"]

      atts[:id] = prefix_id(SecureRandom.hex)
      atts[:parent] = last_id
      last_id = atts[:id]

      atts[:localtype] = sub["type_#{n}"]
      text = sub["indicator_#{n}"]

      xml.container(atts) {
        sanitize_mixed_content(text, xml, fragments)
      }
    end
  end

 # Remove after upgrade.
 def is_digital_object_published?(digital_object, file_version = nil)
    if !digital_object['publish']
      return false
    elsif !file_version.nil? and !file_version['publish']
      return false
    else
      return true
    end
 end

 # keep AS IS during upgrade.  already using the new DAO serializations... but now with URLs and captions.
 def serialize_digital_object(digital_object, xml, fragments)
  return if digital_object["publish"] === false && !@include_unpublished
  return if digital_object["suppressed"] === true

  # ANW-285: Only serialize file versions that are published, unless include_unpublished flag is set
  file_versions_to_display = digital_object['file_versions'].select {|fv| fv['publish'] == true || @include_unpublished }
  title = digital_object['title']
  date = digital_object['dates'][0] || {}

  atts = {}

  content = ""
  content << title if title
  content << ": " if date['expression'] || date['begin']
  if date['expression']
    content << date['expression']
  elsif date['begin']
  content << date['begin']
  if date['end'] != date['begin']
      content << "-#{date['end']}"
    end
  end
  # title is already exported to descriptivenote/p, so no need to try to jam it and duplicate it into an attribute
  atts['linktitle'] = digital_object['digital_object_id'] if digital_object['digital_object_id']
  # and let's keep those URIs everywhere....
  atts['altrender'] = digital_object['uri']

  if digital_object['digital_object_type']
    atts['daotype'] = 'otherdaotype'
    atts['otherdaotype'] = digital_object['digital_object_type']
  else
    atts['daotype'] = 'unknown'
  end

  if file_versions_to_display.empty?
    atts['href'] = digital_object['digital_object_id']
    atts['audience'] = 'internal' unless is_digital_object_published?(digital_object)
    xml.dao(atts) {
      xml.descriptivenote{ sanitize_mixed_content(content, xml, fragments, true) } if content
    }
  elsif file_versions_to_display.length == 1
    file_version = file_versions_to_display.first
    atts['actuate'] = file_version['xlink_actuate_attribute'] || 'onrequest'
    atts['show'] = file_version['xlink_show_attribute'] || 'new'
    atts['linkrole'] = file_version['use_statement'] if file_version['use_statement']
    atts['href'] = file_version['file_uri']
    atts['audience'] = 'internal' unless is_digital_object_published?(digital_object, file_version)
    xml.dao(atts) {
      xml.descriptivenote{ sanitize_mixed_content(content, xml, fragments, true) } if content
    }
  else
    atts['audience'] = 'internal' unless is_digital_object_published?(digital_object)
    # gotta be daoset rather than daogrp for EAD3.... o,k
    xml.daoset( atts ) {
      file_versions_to_display.each do |file_version|
        atts = {}
        atts['actuate'] = file_version['xlink_actuate_attribute'] || 'onrequest'
        atts['show'] = file_version['xlink_show_attribute'] || 'new'
        atts['href'] = file_version['file_uri']
        atts['linkrole'] = file_version['use_statement'] if file_version['use_statement']
        atts['linktitle'] = file_version['caption'] if file_version['caption']
        atts['audience'] = 'internal' unless is_digital_object_published?(digital_object, file_version)
        xml.dao(atts)
      end
      xml.descriptivenote{ sanitize_mixed_content(content, xml, fragments, true) } if content
    }
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

            # Change from EAD 2002: dao must be children of did in EAD3, not archdesc
            data.digital_objects.each do |dob|
              serialize_digital_object(dob, xml, @fragments)
            end

          }# </did>

          serialize_nondid_notes(data, xml, @fragments)

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

      xml.recordid(recordid_atts) {
        xml.text(data.ead_id)
      }

      if data.user_defined && data.user_defined['string_2']
        otherrecordid_atts = { localtype: "BIB" }
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
