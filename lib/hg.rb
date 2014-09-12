class Application
  MERCURIAL_REPOS_PATH = File.realpath(File.join(File.dirname(__FILE__), "..", "repos", "hg"))

  # Mercurial interface
  get '/hg/:repo' do
    require 'zlib'

    if params["cmd"]
      # Run RPC through mercurial app
      allowed_commands      = ["capabilities", "heads", "getbundle", "listkeys"]
      length_strip_commands = ["capabilities", "heads", "listkeys"]
      compressed_commands   = ["getbundle"]
      variadic_commands     = ["getbundle"]

      status 404 and return if not allowed_commands.include? params["cmd"]

      content_type "application/mercurial-0.1"

      path = File.realpath(File.join(MERCURIAL_REPOS_PATH, params[:repo]))
      status 404 and return unless path.start_with? MERCURIAL_REPOS_PATH

      stream do |out|
        query = ""
        if request.env["HTTP_X_HGARG_1"]
          options = request.env["HTTP_X_HGARG_1"].split('&')
          options.map!{|opt| opt.split('=')}

          if variadic_commands.include? params["cmd"]
            query = "* #{options.length}\n"
          end

          query = query + options.map{|opt| "#{opt[0]} #{opt[1].length}\n#{opt[1].gsub('+',' ')}"}.join('')
        end

        query = "\n#{query}" unless query == ""

        compressor = Zlib::Deflate.new
        Dir.chdir(path) do
          command = "hg --config ui.interactive=False serve --stdio"
          IO.popen(command, File::RDWR) do |pipe|
            action = params["cmd"] + query + "\n"
            pipe.write(action)
            pipe.close_write
            while !pipe.eof?
              block = pipe.read(8192) # 8M at a time

              if length_strip_commands.include? params["cmd"]
                # Read and strip out length (it is encoded in http length header field)
                newline = block.index("\n") || -1
                data = block[newline+1..-1]

                # Alter capabilities to limit batching
                if params["cmd"] == "capabilities"
                  data = data.gsub(/\s?batch\s?/, " ").strip
                end

                block = data
              end

              if compressed_commands.include? params["cmd"]
                # stream to the client compressed
                block = compressor.deflate(block)
              end

              # stream to the client
              out << block
            end
          end
          if compressed_commands.include? params["cmd"]
            # Final compressed block
            block = compressor.finish
            out << block
          end
          out.close
          compressor.close
        end
      end
    end
  end
end
