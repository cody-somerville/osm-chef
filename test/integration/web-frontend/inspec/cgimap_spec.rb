describe service("cgimap") do
  it { should be_enabled }
  it { should be_running }
end

describe port(8000) do
  it { should be_listening }
  its("protocols") { should cmp "tcp" }
end
