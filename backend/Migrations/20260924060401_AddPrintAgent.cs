using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace PosApi.Migrations
{
    /// <inheritdoc />
    public partial class AddPrintAgent : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<string>(
                name: "PrintAgentKey",
                table: "Restaurants",
                type: "text",
                nullable: false,
                defaultValue: "");

            // Existing restaurant rows predate this column and got the "" default
            // above — give them a real random key too (new rows always get one
            // from the C# object initializer on insert, this is only a backfill).
            migrationBuilder.Sql(
                "UPDATE \"Restaurants\" SET \"PrintAgentKey\" = md5(random()::text || clock_timestamp()::text) WHERE \"PrintAgentKey\" = ''");
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropColumn(
                name: "PrintAgentKey",
                table: "Restaurants");
        }
    }
}
