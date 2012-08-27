module OpenTox
  class Application < Service

    # get url_for support
    helpers Sinatra::UrlForHelper

    # fix IE
    before {
      request.env['HTTP_ACCEPT'] += ";text/html" if request.env["HTTP_USER_AGENT"]=~/MSIE/
      request.env['HTTP_ACCEPT']=request.params["media"] if request.params["media"]
    }

    # Use the http accept header to decide output format
    # @param [String] a multi-line string
    # @return [String] HTML or plain text
    def format_output (string)
      case request.env['HTTP_ACCEPT']
      when /text\/html/
        content_type "text/html"
        OpenTox.text_to_html string,@subjectid
      else
        content_type 'text/uri-list'
        string
      end
    end

  end
end
