
require "test_helper"

class Inspector::VehiclesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @agency = Agency.create!(name: "Test Agency", code: "TST")
    @password = "Password123!"
    @inspector = User.create!(
      email: "inspector@example.com",
      password: @password,
      password_confirmation: @password,
      role: User::ROLE_VMCOTT_INSPECTOR,
      agency: @agency
    )
  end

  test "lookup redirects to vehicle by registration number" do
    vehicle = Vehicle.create!(
      make: "Toyota",
      model: "Corolla",
      license_plate: "ABC-1234",
      registration_number: "PCL9669",
      agency: @agency
    )

    sign_in_as(@inspector, @password)

    post inspector_vehicle_lookup_path, params: { license_plate: "PCL9669" }

    assert_redirected_to inspector_vehicle_path(vehicle)
  end

  test "lookup normalizes punctuation when matching license plate" do
    vehicle = Vehicle.create!(
      make: "Nissan",
      model: "X-Trail",
      license_plate: "PCL-9669",
      registration_number: nil,
      agency: @agency
    )

    sign_in_as(@inspector, @password)

    post inspector_vehicle_lookup_path, params: { license_plate: " pcl 9669 " }

    assert_redirected_to inspector_vehicle_path(vehicle)
  end

  private

  def sign_in_as(user, password)
    post user_session_path, params: {
      user: {
        email: user.email,
        password: password
      }
    }
    follow_redirect!
    assert_response :success
  end
end
