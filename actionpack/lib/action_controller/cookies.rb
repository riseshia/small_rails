module ActionController #:nodoc:
  # Cookies are read and written through ActionController#cookies. The cookies being read is what was received along with the request,
  # the cookies being written is what will be sent out will the response. Cookies are read by value (so you won't get the cookie object
  # itself back -- just the value it holds). Examples for writting:
  #
  #   cookies["user_name"] = "david" # => Will set a simple session cookie
  #   cookies["login"] = { "value" => "XJ-122", "expires" => Time.now + 360} # => Will set a cookie that expires in 1 hour
  #
  # Examples for reading:
  #
  #   cookies["user_name"] # => "david"
  #   cookies.size         # => 2
  #
  # All the options for setting cookies are:
  #
  # value:: the cookie's value or list of values (as an array).
  # path:: the path for which this cookie applies.  Defaults to the root of the application.
  # domain:: the domain for which this cookie applies.
  # expires:: the time at which this cookie expires, as a +Time+ object.
  # secure:: whether this cookie is a secure cookie or not (default to false).
  #          Secure cookies are only transmitted to HTTPS servers.
  module Cookies
    # Returns the cookie container, which operates as described above.
    def cookies
      CookieContainer.new(self)
    end
  end

  class CookieContainer < Hash #:nodoc:
    def initialize(controller)
      @controller, @cookies = controller, controller.instance_variable_get("@cookies")
      super()
      update(@cookies)
    end

    # Returns the value of the cookie by +name+ -- or nil if no such cookie exist. You set new cookies using either the cookie method
    # or cookies[]= (for simple name/value cookies without options).
    def [](name)
      @cookies[name].value if @cookies[name]
    end

    def []=(name, options)
      if options.is_a?(Hash)
        options["name"] = name
      else
        options = [ name, options ]
      end

      set_cookie(name, options)
    end

    private
      def set_cookie(name, options) #:doc:
        if options.is_a?(Array)
          @controller.response.headers["cookie"] << CGI::Cookie.new(*options)
        else
          @controller.response.headers["cookie"] << CGI::Cookie.new(options)
        end
      end
  end
end
