# Sales Intake

**Purpose**  
Import sales from the legacy system (CSV → system object). Creates the initial sale + product list.

**Use Case**  
User uploads the exported CSV and confirms the sale entry.

**System Implications**  
- Creates the root "Sale" object.
- No editing after creation.
- Access: read-only after import.
- No financial data visibility.


The user will get the data from the old system which is a list of products data about a bought, we then add the suppliers for each one and maybe something more?(check the transcription) -> update bought status
