module ApplicationHelper
  # Generate a sortable link for table headers with Turbo support
  def sortable(column, title = nil)
    title ||= column.titleize

    # Determine the direction for the next click
    direction = (column == params[:sort] && params[:direction] == "asc") ? "desc" : "asc"

    # Add visual indicator if this column is currently sorted
    arrow = if column == params[:sort]
              params[:direction] == "asc" ? " ▲" : " ▼"
            else
              ""
            end

    # Merge current search query and notes filter with sorting params, keep Turbo frame for live updates
    link_to "#{title}#{arrow}".html_safe,
            params.permit(:query, :notes, :page).merge(sort: column, direction: direction),
            data: { turbo_frame: "drivers_table" }
  end

  # Sortable helper for trips table on driver show page
  def sortable_trip(column, title = nil)
    title ||= column.titleize
    direction = (column == params[:trip_sort] && params[:trip_direction] == "asc") ? "desc" : "asc"
    arrow = (column == params[:trip_sort]) ? (params[:trip_direction] == "asc" ? " ▲" : " ▼") : ""
    link_to "#{title}#{arrow}".html_safe,
            params.permit(:trip_page).merge(trip_sort: column, trip_direction: direction),
            data: { turbo_frame: "driver_trips" }
  end
end
