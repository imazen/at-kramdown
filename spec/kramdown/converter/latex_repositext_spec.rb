require_relative '../../helper'

module Kramdown
  module Converter
    describe LatexRepositext do

      describe "#emulate_small_caps" do

        [
          ["Word Word", "W\\RtSmCapsEmulation{ORD} W\\RtSmCapsEmulation{ORD}"],
          ["Wêrd Wêrd", "W\\RtSmCapsEmulation{ÊRD} W\\RtSmCapsEmulation{ÊRD}"],
          ["Word. Word,", "W\\RtSmCapsEmulation{ORD.} W\\RtSmCapsEmulation{ORD},"],
        ].each do |test_string, xpect|
          it "emulates small caps for #{ test_string.inspect }" do
            c = LatexRepositext.send(:new, '_', {})
            c.emulate_small_caps(test_string).must_equal(xpect)
          end
        end

      end

      describe "#convert_entity" do

        [
          ["word &amp; word", "word \\&{} word\n\n"],
          ["word &#x2011; word", "word \u2011 word\n\n"],
          ["word &#x2028; word", "word \u2028 word\n\n"],
          ["word &#x202F; word", "word \u202F word\n\n"],
          ["word &#xFEFF; word", "word \uFEFF word\n\n"],
        ].each do |test_string, xpect|
          it "decodes valid encoded entity #{ test_string.inspect }" do
            doc = Document.new(test_string, :input => 'KramdownRepositext')
            doc.to_latex_repositext.must_equal(xpect)
          end
        end

        [
          ["word &#x2012; word", "word  word\n\n"],
        ].each do |test_string, xpect|
          it "doesn't decode invalid encoded entity #{ test_string.inspect }" do
            doc = Document.new(test_string, :input => 'KramdownRepositext')
            doc.to_latex_repositext.must_equal(xpect)
          end
        end

        [
          ["word &#x391; word", "word $A${} word\n\n"], # decimal 913
        ].each do |test_string, xpect|
          it "decodes kramdown built in entity #{ test_string.inspect }" do
            doc = Document.new(test_string, :input => 'KramdownRepositext')
            doc.to_latex_repositext.must_equal(xpect)
          end
        end

      end

      describe "#escape_latex_text" do

        [
          ["word & word", "word \\& word"],
          ["word % word", "word \\% word"],
          ["word $ word", "word \\$ word"],
          ["word # word", "word \\# word"],
          ["word _ word", "word \\_ word"],
          ["word { word", "word \\{ word"],
          ["word } word", "word \\} word"],
          ["word ~ word", "word \\textasciitilde word"],
          ["word ^ word", "word \\textasciicircum word"],
          ["word \\n word", "word \\textbackslashn word"],
        ].each do |test_string, xpect|
          it "escapes #{ test_string.inspect }" do
            c = LatexRepositext.send(:new, '_', {})
            c.send(:escape_latex_text, test_string).must_equal(xpect)
          end
        end

        [
          ["word \\& word", "word \\& word"],
          ["word \\% word", "word \\% word"],
          ["word \\$ word", "word \\$ word"],
          ["word \\# word", "word \\# word"],
          ["word \\_ word", "word \\_ word"],
          ["word \\{ word", "word \\{ word"],
          ["word \\} word", "word \\} word"],
        ].each do |test_string, xpect|
          it "does not escape already escaped character #{ test_string.inspect }" do
            c = LatexRepositext.send(:new, '_', {})
            c.send(:escape_latex_text, test_string).must_equal(xpect)
          end
        end

      end

    end
  end
end
