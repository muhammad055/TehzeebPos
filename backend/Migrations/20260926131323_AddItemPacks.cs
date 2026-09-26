using Microsoft.EntityFrameworkCore.Migrations;
using Npgsql.EntityFrameworkCore.PostgreSQL.Metadata;

#nullable disable

namespace PosApi.Migrations
{
    /// <inheritdoc />
    public partial class AddItemPacks : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<int>(
                name: "PackId",
                table: "PurchaseItems",
                type: "integer",
                nullable: true);

            migrationBuilder.AddColumn<string>(
                name: "PackName",
                table: "PurchaseItems",
                type: "text",
                nullable: false,
                defaultValue: "");

            migrationBuilder.AddColumn<decimal>(
                name: "PackPrice",
                table: "PurchaseItems",
                type: "numeric",
                nullable: true);

            migrationBuilder.AddColumn<decimal>(
                name: "Packs",
                table: "PurchaseItems",
                type: "numeric",
                nullable: true);

            migrationBuilder.CreateTable(
                name: "ItemPacks",
                columns: table => new
                {
                    Id = table.Column<int>(type: "integer", nullable: false)
                        .Annotation("Npgsql:ValueGenerationStrategy", NpgsqlValueGenerationStrategy.IdentityByDefaultColumn),
                    RestaurantId = table.Column<int>(type: "integer", nullable: false),
                    ItemId = table.Column<int>(type: "integer", nullable: false),
                    Name = table.Column<string>(type: "text", nullable: false),
                    Quantity = table.Column<decimal>(type: "numeric", nullable: false),
                    IsActive = table.Column<bool>(type: "boolean", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_ItemPacks", x => x.Id);
                    table.ForeignKey(
                        name: "FK_ItemPacks_Items_ItemId",
                        column: x => x.ItemId,
                        principalTable: "Items",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateIndex(
                name: "IX_ItemPacks_ItemId",
                table: "ItemPacks",
                column: "ItemId");
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(
                name: "ItemPacks");

            migrationBuilder.DropColumn(
                name: "PackId",
                table: "PurchaseItems");

            migrationBuilder.DropColumn(
                name: "PackName",
                table: "PurchaseItems");

            migrationBuilder.DropColumn(
                name: "PackPrice",
                table: "PurchaseItems");

            migrationBuilder.DropColumn(
                name: "Packs",
                table: "PurchaseItems");
        }
    }
}
