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

end
