# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Reimbursement report activities", type: :system do
  let(:submitter) { create(:user, full_name: "Riley Reimburse") }
  let(:manager) { create(:user, full_name: "Morgan Manager") }
  let(:event) { create(:event, name: "Hack The Seas") }

  before do
    create(:organizer_position_invite, :accepted, event:, user: submitter)
    create(:organizer_position_invite, :accepted, event:, user: manager)
  end

  def report_in(state, name)
    create(:reimbursement_report, user: submitter, event:, name:).tap do |report|
      report.update_columns(aasm_state: state)
    end
  end

  # `rails_helper` turns tracking off in the spec's thread, so turn it back on
  # while setting up. The app server's threads track by default.
  def track(&)
    PublicActivity.with_tracking(&)
  end

  context "with a report in every final state" do
    # Submitting and approving go through guards and payouts that the model
    # spec already covers, so log those two directly. These specs check how
    # each activity renders.
    before do
      track do
        create(:reimbursement_report, user: submitter, event:, name: "Stickers").create_activity(key: "reimbursement_report.submitted", owner: submitter, recipient: event, event_id: event.id)
        approved = report_in("reimbursement_requested", "Pizza")
        approved.create_activity(key: "reimbursement_report.approved", owner: submitter, recipient: submitter, event_id: event.id)
        report_in("reimbursement_approved", "Snacks").mark_reimbursed!
        report_in("submitted", "Tape").mark_rejected!(rejected_by: manager)
        report_in("reimbursed", "Batteries").mark_reversed!
      end
    end

    it "tells the submitter what happened to each report in their feed" do
      sign_in(submitter)
      visit my_activities_path

      expect(page).to have_text("You submitted Stickers for reimbursement from Hack The Seas")
      expect(page).to have_text("Your report Pizza on Hack The Seas was approved")
      expect(page).to have_text("You were reimbursed for Snacks on Hack The Seas")
      expect(page).to have_text("Morgan Manager rejected your report Tape on Hack The Seas")
      expect(page).to have_text("Your reimbursement for Batteries failed, so the money went back to Hack The Seas")
    end

    it "shows the same activities in the organization's audit log" do
      sign_in(manager)
      visit edit_event_path(event, tab: "audit_log")

      expect(page).to have_text("Riley Reimburse submitted Stickers for reimbursement from Hack The Seas")
      expect(page).to have_text("Riley Reimburse's report Pizza on Hack The Seas was approved")
      expect(page).to have_text("Riley Reimburse was reimbursed for Snacks on Hack The Seas")
      expect(page).to have_text("You rejected Riley Reimburse's report Tape on Hack The Seas")
      expect(page).to have_text("Riley Reimburse's reimbursement for Batteries failed, so the money went back to Hack The Seas")
    end
  end

  it "credits a rejection from the report page to the manager who clicked it" do
    report = report_in("submitted", "Tape")

    sign_in(manager)
    visit reimbursement_report_path(report)
    click_on "Reject & close report"
    expect(page).to have_text("Rejected & closed the report")

    visit edit_event_path(event, tab: "audit_log")
    expect(page).to have_text("You rejected Riley Reimburse's report Tape on Hack The Seas")
  end
end
