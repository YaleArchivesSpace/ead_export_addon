# encoding: utf-8

class EAD3Serializer < EADSerializer
  serializer_for :ead3

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


  def strip_p(content)
    content = escape_ampersands(content)
    content.gsub("<p>", "").gsub("</p>", "").gsub("<p/>", '')
  end

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
