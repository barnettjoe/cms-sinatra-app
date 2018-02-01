require "sinatra"
require "sinatra/contrib"
require "sinatra/reloader" if development?
require "erubis"
require "redcarpet"
require "yaml"
require "bcrypt"

enable :sessions
set :session_secret, 'super secret'

def data_path
  if ENV["RACK_ENV"] == "test"
    File.expand_path("../test/data", __FILE__)
  else
    File.expand_path("../data", __FILE__)
  end
end

def load_user_credentials
  credentials_path =
    if ENV["RACK_ENV"] == "test"
      File.expand_path("../test/users.yml", __FILE__)
    else
      File.expand_path("../users.yml", __FILE__)
    end
  YAML.load_file(credentials_path)
end

def create_document(name, content = "")
  File.open(File.join(data_path, name), "w") do |file|
    file.write(content)
  end
end

def valid?(name)
  name[/\S/]
end

helpers do
  def render_markdown(raw)
    markdown = Redcarpet::Markdown.new(Redcarpet::Render::HTML)
    markdown.render(raw)
  end
end

def signed_in?
  session[:user]
end

def signed_in_only
  if signed_in?
    yield
  else
    session[:flash] = "You must be signed in to do that"
    redirect "/"
  end
end

before do
  pattern = File.join(data_path, "*")
  @files = Dir.glob(pattern).map { |file| File.basename(file) }
end

get "/" do
  erb :home
end

get "/users/signin" do
  erb :signin
end

def correct?(stored_hash, password)
  restored_hash = BCrypt::Password.new(stored_hash)
  restored_hash == password
end

post "/signin" do
  users = load_user_credentials
  username = params[:username]
  password = params[:password]
  stored_hash = users[username]
  if stored_hash && correct?(stored_hash, password)
    session[:user] = username
    session[:flash] = "Welcome!"
    redirect "/"
  else
    status 422
    session[:flash] = "invalid credentials"
    erb :signin
  end
end

post '/signout' do
  session.delete(:user)
  session[:flash] = "you have been signed out"
  redirect "/"
end

get "/new" do
  signed_in_only do
    erb :new
  end
end

post "/new" do
  signed_in_only do
    doc_name = params[:file_name]
    if valid?(doc_name)
      session[:flash] = "made new file: #{doc_name}"
      create_document(doc_name)
      redirect "/"
    else
      session[:flash] = "A name is required."
      status 422
      erb :new
    end
  end
end

get "/:file" do
  file = params[:file]
  if @files.include? file
    file_path = File.join(data_path, file)
    show(file_path)
  else
    session[:flash] = "#{file} does not exist."
    redirect "/"
  end
end

get "/:file/edit" do
  signed_in_only do
    file = params[:file]
    file_path = File.join(data_path, file)
    @txt = File.read(file_path)
    erb :edit
  end
end

post '/:file/delete' do
  signed_in_only do
    file = params[:file]
    file_path = File.join(data_path, file)
    File.delete file_path
    session[:flash] = "#{file} was deleted."
    redirect "/"
  end
end

post '/:file/edit' do
  signed_in_only do
    file = params[:file]
    file_path = File.join(data_path, file)
    File.write(file_path, params[:content])
    session[:flash] = "#{file} has been updated."
    redirect "/"
  end
end

def show(file_path)
  raw = File.read(file_path)
  if File.extname(file_path) == ".md"
    headers["Content-Type"] = "text/html"
    render_markdown(raw)
  else
    headers["Content-Type"] = "text/plain"
    raw
  end
end