# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Nanobot do
  it 'has a version number' do
    expect(Nanobot::VERSION).not_to be_nil
  end
end
