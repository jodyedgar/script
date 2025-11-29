# Notion QA Fields Specification

This document specifies the fields that should be added to the Notion Tickets database to enable QA process recording.

## Required Fields

### 1. QA Status (Status)
**Type:** Status
**Group:** QA Verification

**Options:**
| Status | Color | Description |
|--------|-------|-------------|
| Pending QA | Gray | Work complete, awaiting QA verification |
| QA In Progress | Blue | QA reviewer is currently testing |
| QA Passed | Green | Changes verified and approved |
| QA Failed | Red | Issues found, needs fixes |
| QA Skipped | Yellow | QA not required for this ticket |

**Automation:**
- Auto-set to "Pending QA" when Ticket Status changes to "Ready for QA"
- Block completion if QA Status is not "Passed" or "Skipped"

---

### 2. QA Approved By (Person)
**Type:** Person
**Description:** Who performed the QA verification

**Notes:**
- Should be a team member
- Required when QA Status = "Passed" or "Failed"

---

### 3. QA Completed Time (Date)
**Type:** Date
**Description:** When QA verification was completed

**Auto-fill:** Set automatically when QA Status changes to "Passed" or "Failed"

---

### 4. Staging Preview URL (URL)
**Type:** URL
**Description:** Link to preview changes on staging/development theme

**Format:** `https://store.myshopify.com/?preview_theme_id=XXXXXXX`

**Notes:**
- Can be auto-generated from Shopify Theme ID
- Should include page path for specific ticket (e.g., `/products/...` for PDP tickets)

---

### 5. QA Evidence (Files & Media)
**Type:** Files & Media
**Description:** Screenshots, recordings, or other proof of verification

**Accepted formats:**
- Images: PNG, JPG, GIF
- Videos: MP4, MOV
- Documents: PDF

**Naming convention:** `TICK-####_QA_[description].[ext]`

---

### 6. QA Notes (Rich Text)
**Type:** Rich Text (in page body, not property)
**Description:** Detailed QA observations, issues found, or feedback

**Template:**
```
## QA Verification

**Status:** [Passed/Failed]
**Tested by:** [Name]
**Date:** [Date]
**Environment:** [Browser, Device, Viewport]

### Observations
- [Observation 1]
- [Observation 2]

### Issues Found
- [ ] Issue 1
- [ ] Issue 2

### Screenshots
[Attached below]
```

---

### 7. QA Environment (Multi-select)
**Type:** Multi-select
**Description:** Browsers, devices, and viewports tested

**Options:**
| Option | Category |
|--------|----------|
| Chrome Desktop | Browser |
| Safari Desktop | Browser |
| Firefox Desktop | Browser |
| Chrome Mobile | Browser |
| Safari Mobile | Browser |
| iPhone | Device |
| iPad | Device |
| Android Phone | Device |
| Android Tablet | Device |
| 1920px | Viewport |
| 1440px | Viewport |
| 1024px | Viewport |
| 768px | Viewport |
| 480px | Viewport |
| 375px | Viewport |

---

### 8. QA Batch ID (Text)
**Type:** Text
**Description:** Groups tickets that were QA'd together in a batch

**Format:** `QA-YYYYMMDD-HHMMSS` or `QA-[batch-key]-[timestamp]`

**Example:** `QA-pdp-P1-QuickWins-20251128-093000`

---

## Field Relationships

```
Ticket Status: "Complete"
       ↓
  requires
       ↓
QA Status: "Passed" or "Skipped"
       ↓
  requires
       ↓
QA Approved By: [Person]
QA Completed Time: [Date]
```

---

## Implementation Steps

### Step 1: Add Status Property
1. Open Notion Tickets database
2. Add new property → Status
3. Name: "QA Status"
4. Add status options as listed above
5. Set default to blank (no default)

### Step 2: Add Person Property
1. Add new property → Person
2. Name: "QA Approved By"
3. Allow multiple people: No

### Step 3: Add Date Property
1. Add new property → Date
2. Name: "QA Completed Time"
3. Include time: Yes

### Step 4: Add URL Property
1. Add new property → URL
2. Name: "Staging Preview URL"

### Step 5: Add Multi-select Property
1. Add new property → Multi-select
2. Name: "QA Environment"
3. Add options as listed above

### Step 6: Add Text Property
1. Add new property → Text
2. Name: "QA Batch ID"

### Step 7: Update Page Template
1. Edit ticket page template
2. Add QA Verification section
3. Include template text for QA notes

---

## Script Integration

After adding fields, the following scripts will be able to update them:

| Script | Fields Updated |
|--------|---------------|
| `record-qa.sh` | QA Status, QA Notes (page content), QA Batch ID |
| `complete-batch.sh` | Validates QA Status before completion |
| `batch_workflow.sh` | Orchestrates QA workflow |

**Note:** Due to Notion API limitations, some fields (like QA Approved By as Person) may need to be updated manually or through additional API configuration.

---

## Verification Checklist

After implementing, verify with:

```bash
./tests/test_qa_process_recording.sh
```

All checks should pass once fields are added.
