require "test_helper"

# Uses the same embedded chunks as the eval (see test/evals/retrieval_eval_test.rb).
class SearchControllerTest < ActionDispatch::IntegrationTest
  test "empty page renders" do
    get root_path
    assert_response :success
    assert_select "h1", "Ask the Rails Guides"
  end

  test "an out-of-scope question says it is not covered" do
    get root_path(q: "best hiking trails in Patagonia")
    assert_select ".verdict.is-not-covered h3", "Not covered in the Guides"
    assert_select ".column", 2
    assert_select ".result.is-past-cutoff", 5
  end

  test "an in-scope question cites a guide" do
    get root_path(q: "run code only after the database transaction commits")
    assert_select ".verdict.is-covered h3 a[href^='https://guides.rubyonrails.org/']"
  end
end
