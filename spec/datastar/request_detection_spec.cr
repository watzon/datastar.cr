require "../spec_helper"

describe Datastar::RequestDetection do
  it "detects datastar request via header" do
    headers = HTTP::Headers{"Datastar-Request" => "true"}
    request = HTTP::Request.new("GET", "/", headers)

    Datastar::RequestDetection.datastar_request?(request).should be_true
  end

  it "detects datastar request via query param" do
    request = HTTP::Request.new("GET", "/?datastar=%7B%7D")

    Datastar::RequestDetection.datastar_request?(request).should be_true
  end

  it "returns false without header or query param" do
    request = HTTP::Request.new("GET", "/")

    Datastar::RequestDetection.datastar_request?(request).should be_false
  end

  it "allows custom header names and values" do
    headers = HTTP::Headers{"X-Custom" => "datastar"}
    request = HTTP::Request.new("POST", "/", headers)

    Datastar::RequestDetection.datastar_request?(
      request,
      header_names: ["X-Custom"],
      header_values: ["datastar"],
      check_query: false
    ).should be_true
  end
end
