ENV["RACK_ENV"] = "test"

require "minitest/autorun"
require "rack/test"
require "fileutils"


require_relative "../cms"

class CMSTest < Minitest::Test
  include Rack::Test::Methods

  def app
    Sinatra::Application
  end

  def setup
    FileUtils.mkdir_p(data_path)
  end

  def session
    last_request.env["rack.session"]
  end

  def admin_session
    { "rack.session" => { user: "admin" } }
  end

  def test_home
    create_document "about.md"
    create_document "changes.txt"
    get "/"
    assert_equal last_response.status, 200
    assert_equal "text/html;charset=utf-8", last_response["Content-Type"]
    assert_includes last_response.body, "about.md"
  end

  def test_history
    create_document "history.txt", "Matsumoto"
    get "/history.txt"
    assert_equal last_response.status, 200
    assert_equal "text/plain", last_response["Content-Type"]
    assert_includes last_response.body, "Matsumoto"
  end

  def test_document_not_found
    get "/notafile.ext" # Attempt to access a nonexistent file
    assert_equal 302, last_response.status # Assert that the user was redirected
    assert_equal session[:flash], "notafile.ext does not exist."
  end

  def test_markdown_rendering
    create_document "about.md", "### lorem ipsum"
    create_document "changes.txt", "### lorem ipsum"
    get "/about.md"
    assert last_response.ok?
    assert_includes last_response.body, "<h3>"
    get "/changes.txt"
    assert last_response.ok?
    assert_includes last_response.body, "###"
  end

  def test_render_edit_page_admin
    create_document "about.md", "### lorem ipsum"
    get "/about.md/edit", {}, admin_session
    assert last_response.ok?
    assert_includes last_response.body, "<textarea"
    session.clear
  end

  def test_render_edit_page_signed_out
    create_document "about.md", "### lorem ipsum"
    get "/about.md/edit"
    assert_equal 302, last_response.status
    assert_equal session[:flash], "You must be signed in to do that"
  end

  def test_edit_document_admin
    create_document "history.txt", "lorem ipsum"
    post "/history.txt/edit", { content: "Matsumoto new content" }, admin_session
    assert_equal 302, last_response.status
    assert_equal session[:flash], "history.txt has been updated."
    get "/history.txt"
    assert_equal 200, last_response.status
    assert_includes last_response.body, "new content"
    session.clear
  end

  def test_edit_document_signed_out
    create_document "history.txt", "lorem ipsum"
    post "/history.txt/edit", { content: "Matsumoto new content" }
    assert_equal 302, last_response.status
    assert_equal "You must be signed in to do that", session[:flash]
  end

  def test_view_new_document_form_admin
    get "/new", {}, admin_session
    assert_equal 200, last_response.status
    assert_includes last_response.body, "<input"
    assert_includes last_response.body, "Create"
    session.clear
  end

  def test_view_new_document_form_admin
    get "/new"
    assert_equal 302, last_response.status
    assert_equal session[:flash], "You must be signed in to do that"
  end

  def test_create_new_document_admin
    post "/new", { file_name: "test.txt" }, admin_session
    assert_equal 302, last_response.status
    assert_equal session[:flash], "made new file: test.txt"
    get "/"
    assert_includes last_response.body, "test.txt"
    session.clear
  end

  def test_create_new_document_signed_out
    post "/new", file_name: "test.txt"
    assert_equal 302, last_response.status
    assert_equal session[:flash], "You must be signed in to do that"
  end

  def test_create_new_document_without_filename
    post "/new", { file_name: "" }, admin_session
    assert_equal 422, last_response.status
    assert_includes last_response.body, "name is required"
  end

  def test_deleting_document_admin
    create_document("test.txt")
    post "/test.txt/delete", {}, admin_session
    assert_equal 302, last_response.status
    assert_equal "test.txt was deleted.", session[:flash]
    session.clear
  end

  def test_deleting_document_signed_out
    create_document("test.txt")
    post "/test.txt/delete"
    assert_equal 302, last_response.status
    assert_equal session[:flash], "You must be signed in to do that"
  end

  def test_signin_admin
    post "/signin", username: "admin", password: "secret"
    assert_equal 302, last_response.status
    assert_equal "Welcome!", session[:flash]
    assert_equal "admin", session[:user]
    get last_response["Location"]
    assert_includes last_response.body, "Signed in as admin"
  end

  def test_signin_other_user
    post "/signin", { username: "bill", password: "billspassword" }
    assert_equal 302, last_response.status
    assert_equal "Welcome!", session[:flash]
    assert_equal "bill", session[:user]
    get last_response["Location"]
    assert_includes last_response.body, "Signed in as bill"
  end

  def test_signin_form
    get "/users/signin"
    assert_equal 200, last_response.status
    assert_includes last_response.body, "<input"
    assert_includes last_response.body, "<button>"
  end

  def test_signin_with_bad_credentials
    post "/signin", username: "guest", password: "shhh"
    assert_equal 422, last_response.status
    assert_nil session[:user]
    assert_includes last_response.body, "invalid credentials"
  end

  def test_signout
    post "/signout", {}, {"rack.session" => {username: "admin", password: "secret"} }
    get last_response["Location"]
    assert_includes last_response.body, "you have been signed out"
    assert_includes last_response.body, "Sign In"
  end

  def teardown
    FileUtils.rm_rf(data_path)
  end
end